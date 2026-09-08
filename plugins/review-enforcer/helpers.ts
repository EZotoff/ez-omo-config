/**
 * Pure gating helpers for review-enforcer — NOT a plugin module.
 *
 * WHY THIS FILE EXISTS (2026-09-08 incident): OpenCode's plugin loader
 * (packages/opencode/src/plugin/index.ts — getLegacyPlugins, semantics
 * unchanged since at least v1.17.9) treats EVERY function export of a plugin
 * module as a plugin constructor and calls it with (PluginInput, options).
 * review-enforcer.ts exporting these helpers for its unit-test harness meant
 * every fresh server called detectRecursion(PluginInput, ...) →
 * `output.includes is not a function` → "failed to load plugin
 * review-enforcer" on every boot, and the damaged load intermittently lost
 * the startup race so sessions died with `default agent "Sisyphus" not found`.
 *
 * RULE: any module on the plugin surface (top-level ~/.opencode/plugin/*.ts
 * auto-discovery, or entries in opencode.json#plugin) may export ONLY the
 * plugin function plus `default`. Test-importable pure helpers live here,
 * one level below the plugin entry file — the loader never auto-loads
 * subdirectories.
 */

const FAILURE_MARKERS = [
	"Task failed",
	"TASK FAILED",
	"Verification failed",
	"Poll timeout reached",
] as const

const SUCCESS_INDICATOR = "## SUBAGENT WORK COMPLETED"

const RECURSION_MARKERS = [
	"[REVIEW-TASK]",
	"[REVIEW-FIX]",
	"[DEBATE]",
] as const

/** Consultative subagents produce analysis, not implementation — code-review mandates don't apply. */
const CONSULTATIVE_SUBAGENT_TYPES = new Set([
	"oracle",
	"metis",
	"momus",
	"explore",
	"librarian",
	"multimodal-looker",
	"document-writer",
])

/** Category-routed dispatches that are consultative (analysis-only). Debate judge categories (artistry/writing/ultrabrain) also do implementation work elsewhere, so they are covered by the [DEBATE] dispatch marker instead. */
const CONSULTATIVE_CATEGORIES = new Set(["mephistopheles"])

/** Outputs shorter than this without the success indicator carry no reviewable work. */
const DEGENERATE_OUTPUT_THRESHOLD = 250

/** Boulder statuses that must never trigger the plan-complete injection. "completed" is allowed — the injection fires at the completion moment, before completeBoulder runs. */
const INACTIVE_BOULDER_STATUSES = new Set(["paused", "abandoned"])

export function detectFailure(output: string): string | null {
	for (const marker of FAILURE_MARKERS) {
		if (output.includes(marker)) {
			return marker
		}
	}
	return null
}

export function detectRecursion(output: string, argsStr: string): string | null {
	for (const marker of RECURSION_MARKERS) {
		if (output.includes(marker) || argsStr.includes(marker)) {
			return marker
		}
	}
	return null
}

export function safeStringifyArgs(args: unknown): string {
	try {
		if (typeof args === "string") return args
		return JSON.stringify(args) ?? ""
	} catch {
		return ""
	}
}

/** Mirrors OMO's normalizeSessionId: bare opencode session ids get the "opencode:" prefix. */
export function normalizeSessionId(sessionId: string): string {
	return sessionId.startsWith("opencode:") ? sessionId : `opencode:${sessionId}`
}

/** True when the dispatch targets a consultative (analysis-only) subagent. Accepts args as object or JSON string. */
export function isConsultativeDispatch(args: unknown): boolean {
	let parsed: Record<string, unknown>
	if (typeof args === "string") {
		try {
			parsed = JSON.parse(args) as Record<string, unknown>
		} catch {
			return false
		}
	} else if (args !== null && typeof args === "object") {
		parsed = args as Record<string, unknown>
	} else {
		return false
	}
	for (const key of ["subagent_type", "agent"]) {
		const value = parsed[key]
		if (typeof value === "string" && CONSULTATIVE_SUBAGENT_TYPES.has(value)) return true
	}
	const category = parsed["category"]
	if (typeof category === "string" && CONSULTATIVE_CATEGORIES.has(category)) return true
	return false
}

/** True when currentSessionId belongs to the boulder's session lineage (root mirror session_ids). */
export function sessionOwnsBoulder(currentSessionId: string, sessionIds: readonly string[]): boolean {
	if (sessionIds.length === 0) return false
	const normalized = normalizeSessionId(currentSessionId)
	return sessionIds.some((id) => normalizeSessionId(id) === normalized)
}

/** Legacy mirror files carry no status — only paused/abandoned block injection. */
export function boulderStatusAllowsInjection(status: unknown): boolean {
	if (typeof status !== "string") return true
	return !INACTIVE_BOULDER_STATUSES.has(status)
}

/** True for OMO sync-task abort stubs: a task that died of provider exhaustion / fallback-chain abort returns 'Aborted\n\nto continue: task(task_id=...' — a failure, not a completion. */
export function isAbortStub(output: string): boolean {
	return output.startsWith("Aborted") || output.includes("to continue: task(task_id=")
}

/** True for near-empty outputs without the positive success indicator — nothing reviewable. */
export function isDegenerateOutput(output: string): boolean {
	if (output.includes(SUCCESS_INDICATOR)) return false
	return output.length < DEGENERATE_OUTPUT_THRESHOLD
}

export { FAILURE_MARKERS, SUCCESS_INDICATOR, RECURSION_MARKERS }
