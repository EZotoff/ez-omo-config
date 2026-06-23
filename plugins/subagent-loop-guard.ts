/**
 * Subagent Loop Guard plugin.
 *
 * Repo evidence state: repo_implemented when tracked here; configured to block
 * bash calls and configured to log warnings only after install/registration.
 * Not verified live: runtime_loaded, real_project_behavior_proven.
 */

import type { Plugin } from "@opencode-ai/plugin"

const DEFAULTS = { ringSize: 50, windowA: 50, nA: 30, windowB: 30, nB: 20, infoThreshold: 300, cooldownMs: 60_000, sessionTtlMs: 30 * 60 * 1000, sessionCallLimit: 1_000 } as const
const RULE_IDS = { toolFrequency: "A", varyingInput: "B", infoThreshold: "C" } as const

type RuleID = (typeof RULE_IDS)[keyof typeof RULE_IDS]
type LogLevel = "debug" | "info" | "warn" | "error"
type Env = Readonly<Record<string, string | undefined>>
type LogSink = (level: LogLevel, message: string) => void | Promise<void>

export type LoopGuardBeforeInput = { readonly tool: string; readonly sessionID: string; readonly callID: string }
export type LoopGuardBeforeOutput = { args: Record<string, unknown> }
export type LoopGuardAfterInput = LoopGuardBeforeInput & { readonly args: Record<string, unknown> }
export type LoopGuardAfterOutput = { readonly title: string; readonly output: string; readonly metadata: unknown }

type LoopGuardBeforeHook = (input: LoopGuardBeforeInput, output: LoopGuardBeforeOutput) => Promise<void>
type LoopGuardAfterHook = (input: LoopGuardAfterInput, output: LoopGuardAfterOutput) => Promise<void>

export type ToolCallEntry = { readonly tool: string; readonly callID: string; readonly sessionID: string; readonly argsSignature: string; readonly timestamp: number }
type LoopGuardConfig = { readonly enabled: boolean; readonly windowA: number; readonly nA: number; readonly windowB: number; readonly nB: number; readonly infoThreshold: number; readonly cooldownMs: number }
type Detection = { readonly ruleID: RuleID; readonly reason: string }
type SessionState = { readonly entries: RingBuffer<ToolCallEntry>; readonly seenCallIDs: Set<string>; readonly cooldownUntilByRule: Map<RuleID, number>; totalCalls: number; lastTouchedAt: number }
type LoopGuardOptions = { readonly env?: Env; readonly now?: () => number; readonly log?: LogSink }
export type LoopGuardSnapshot = { readonly entries: readonly ToolCallEntry[]; readonly totalCalls: number }
export type LoopGuardTestHarness = { readonly before: LoopGuardBeforeHook; readonly after: LoopGuardAfterHook; readonly snapshot: (sessionID: string) => LoopGuardSnapshot | null; readonly injectFaultOnce: () => void }

class LoopGuardFault extends Error {
	constructor() {
		super("injected loop guard hook fault")
		this.name = "LoopGuardFault"
	}
}

class RingBuffer<T> {
	readonly #limit: number
	readonly #items: T[] = []
	constructor(limit: number) { this.#limit = limit }
	push(item: T): T | undefined {
		this.#items.push(item)
		if (this.#items.length <= this.#limit) return undefined
		return this.#items.shift()
	}
	values(): readonly T[] { return this.#items }
}

function readPositiveInteger(env: Env, key: string, fallback: number): number {
	const raw = env[key]
	if (!raw) return fallback
	const parsed = Number.parseInt(raw, 10)
	return Number.isInteger(parsed) && parsed > 0 ? parsed : fallback
}

function readConfig(env: Env): LoopGuardConfig {
	return {
		enabled: env.OMO_LOOP_GUARD_DISABLE !== "1",
		windowA: readPositiveInteger(env, "OMO_LOOP_GUARD_WINDOW_A", DEFAULTS.windowA),
		nA: readPositiveInteger(env, "OMO_LOOP_GUARD_N_A", DEFAULTS.nA),
		windowB: readPositiveInteger(env, "OMO_LOOP_GUARD_WINDOW_B", DEFAULTS.windowB),
		nB: readPositiveInteger(env, "OMO_LOOP_GUARD_N_B", DEFAULTS.nB),
		infoThreshold: readPositiveInteger(env, "OMO_LOOP_GUARD_INFO_THRESHOLD", DEFAULTS.infoThreshold),
		cooldownMs: readPositiveInteger(env, "OMO_LOOP_GUARD_COOLDOWN_MS", DEFAULTS.cooldownMs),
	}
}

function isRecord(value: unknown): value is Record<string, unknown> {
	return typeof value === "object" && value !== null && !Array.isArray(value)
}

function stableStringify(value: unknown): string {
	if (value === null || typeof value !== "object") return JSON.stringify(value)
	if (Array.isArray(value)) return `[${value.map((item) => stableStringify(item)).join(",")}]`
	const fields = Object.entries(value)
		.sort(([left], [right]) => left.localeCompare(right))
		.map(([key, fieldValue]) => `${JSON.stringify(key)}:${stableStringify(fieldValue)}`)
	return `{${fields.join(",")}}`
}

function makeEntry(input: { readonly tool: string; readonly sessionID: string; readonly callID: string; readonly args: unknown }, timestamp: number): ToolCallEntry {
	return {
		tool: input.tool,
		callID: input.callID,
		sessionID: input.sessionID,
		argsSignature: stableStringify(input.args),
		timestamp,
	}
}

function createSession(): SessionState {
	return {
		entries: new RingBuffer<ToolCallEntry>(DEFAULTS.ringSize),
		seenCallIDs: new Set<string>(),
		cooldownUntilByRule: new Map<RuleID, number>(),
		totalCalls: 0,
		lastTouchedAt: 0,
	}
}

function windowEntries(entries: readonly ToolCallEntry[], size: number): readonly ToolCallEntry[] { return entries.slice(Math.max(0, entries.length - size)) }

function mostFrequentTool(entries: readonly ToolCallEntry[]): { readonly tool: string; readonly count: number } | null {
	const counts = new Map<string, number>()
	for (const entry of entries) counts.set(entry.tool, (counts.get(entry.tool) ?? 0) + 1)
	let leader: { readonly tool: string; readonly count: number } | null = null
	for (const [tool, count] of counts) {
		if (!leader || count > leader.count) leader = { tool, count }
	}
	return leader
}

function hasAdjacentSignatureRepeat(entries: readonly ToolCallEntry[]): boolean {
	for (let index = 1; index < entries.length; index++) {
		if (entries[index - 1]?.argsSignature === entries[index]?.argsSignature) return true
	}
	return false
}

function inCooldown(state: SessionState, ruleID: RuleID, now: number): boolean { return (state.cooldownUntilByRule.get(ruleID) ?? 0) > now }

function markCooldown(state: SessionState, detection: Detection, config: LoopGuardConfig, now: number): Detection | null {
	if (inCooldown(state, detection.ruleID, now)) return null
	state.cooldownUntilByRule.set(detection.ruleID, now + config.cooldownMs)
	return detection
}

function detectBlocking(state: SessionState, config: LoopGuardConfig, now: number): Detection | null {
	const entries = state.entries.values()
	const ruleAWindow = windowEntries(entries, config.windowA)
	const ruleALeader = mostFrequentTool(ruleAWindow)
	if (ruleALeader && ruleALeader.count > config.nA) {
		return markCooldown(state, {
			ruleID: RULE_IDS.toolFrequency,
			reason: `rule A tool-frequency alternation: ${ruleALeader.tool} appeared ${ruleALeader.count} times in last ${ruleAWindow.length} calls`,
		}, config, now)
	}

	const ruleBWindow = windowEntries(entries, config.windowB)
	const ruleBLeader = mostFrequentTool(ruleBWindow)
	if (ruleBLeader && ruleBLeader.count > config.nB && !hasAdjacentSignatureRepeat(ruleBWindow)) {
		return markCooldown(state, {
			ruleID: RULE_IDS.varyingInput,
			reason: `rule B same-tool varying-input: ${ruleBLeader.tool} appeared ${ruleBLeader.count} times without adjacent repeated args`,
		}, config, now)
	}

	return null
}

function sanitizeReason(reason: string): string { return reason.replace(/["`$\\]/g, "_").replace(/[\r\n]/g, " ") }

function mutateBashCommand(output: LoopGuardBeforeOutput, reason: string): void {
	const args: unknown = output.args
	if (!isRecord(args) || typeof args.command !== "string") return
	args.command = `echo "[loop-guard] blocked: ${sanitizeReason(reason)}"`
}

function formatError(error: unknown): string { return error instanceof Error ? error.message : String(error) }

function createLoopGuard(options: LoopGuardOptions = {}): LoopGuardTestHarness {
	const config = readConfig(options.env ?? process.env)
	const now = options.now ?? Date.now
	const log = options.log ?? (() => undefined)
	const sessions = new Map<string, SessionState>()
	let faultArmed = false

	const emitLog = (level: LogLevel, message: string): void => {
		void Promise.resolve(log(level, message)).catch((error: unknown) => {
			console.error(`[subagent-loop-guard] log failure: ${formatError(error)}`)
		})
	}

	const pruneStaleSessions = (timestamp: number): void => {
		for (const [sessionID, state] of sessions) {
			if (timestamp - state.lastTouchedAt > DEFAULTS.sessionTtlMs) sessions.delete(sessionID)
		}
	}

	const getSession = (sessionID: string, timestamp: number): SessionState => {
		pruneStaleSessions(timestamp)
		let state = sessions.get(sessionID)
		if (!state) {
			state = createSession()
			sessions.set(sessionID, state)
		}
		state.lastTouchedAt = timestamp
		return state
	}

	const record = (entry: ToolCallEntry): SessionState => {
		const state = getSession(entry.sessionID, entry.timestamp)
		if (state.seenCallIDs.has(entry.callID)) return state
		const evicted = state.entries.push(entry)
		if (evicted) state.seenCallIDs.delete(evicted.callID)
		state.seenCallIDs.add(entry.callID)
		state.totalCalls += 1
		return state
	}

	const maybeEvictFullSession = (sessionID: string): void => {
		const state = sessions.get(sessionID)
		if (state && state.totalCalls >= DEFAULTS.sessionCallLimit) sessions.delete(sessionID)
	}

	const raiseFaultIfArmed = (): void => {
		if (!faultArmed) return
		faultArmed = false
		throw new LoopGuardFault()
	}

	return {
		before: async (input, output) => {
			if (!config.enabled) return
			try {
				raiseFaultIfArmed()
				const timestamp = now()
				const entry = makeEntry({ ...input, args: output.args }, timestamp)
				const state = record(entry)
				const detection = detectBlocking(state, config, timestamp)
				if (detection) {
					emitLog("warn", `configured to block loop pattern — session=${input.sessionID}, ${detection.reason}`)
					if (input.tool === "bash") mutateBashCommand(output, detection.reason)
				}
				maybeEvictFullSession(input.sessionID)
			} catch (error) {
				emitLog("error", `fail-open: tool.execute.before error — ${formatError(error)}`)
			}
		},
		after: async (input, _output) => {
			if (!config.enabled) return
			try {
				raiseFaultIfArmed()
				const timestamp = now()
				const state = record(makeEntry(input, timestamp))
				if (state.totalCalls > config.infoThreshold) {
					const detection = markCooldown(state, {
						ruleID: RULE_IDS.infoThreshold,
						reason: `rule C informational threshold: session recorded ${state.totalCalls} tool calls`,
					}, config, timestamp)
					if (detection) emitLog("warn", `configured to log warning — session=${input.sessionID}, ${detection.reason}`)
				}
				maybeEvictFullSession(input.sessionID)
			} catch (error) {
				emitLog("error", `fail-open: tool.execute.after error — ${formatError(error)}`)
			}
		},
		snapshot: (sessionID) => {
			const state = sessions.get(sessionID)
			return state ? { entries: state.entries.values(), totalCalls: state.totalCalls } : null
		},
		injectFaultOnce: () => {
			faultArmed = true
		},
	}
}

export function createLoopGuardForTest(options: LoopGuardOptions = {}): LoopGuardTestHarness {
	return createLoopGuard(options)
}

export const SubagentLoopGuardPlugin: Plugin = async (ctx) => {
	const guard = createLoopGuard({
		log: (level, message) => {
			void ctx.client.app.log({ body: { service: "subagent-loop-guard", level, message } }).catch((error: unknown) => {
				console.error(`[subagent-loop-guard] OpenCode log failure: ${formatError(error)}`)
			})
		},
	})

	return {
		"tool.execute.before": guard.before,
		"tool.execute.after": guard.after,
	}
}

export default SubagentLoopGuardPlugin
