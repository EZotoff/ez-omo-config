import { appendFileSync, mkdirSync, readFileSync, renameSync, statSync, unlinkSync } from "node:fs"
import { dirname } from "node:path"
import { execSync } from "node:child_process"
import type { Plugin } from "@opencode-ai/plugin"

/**
 * Review Enforcer Plugin — intercepts task() completions via tool.execute.after
 * and injects review instructions into the output that Atlas sees.
 *
 * Skips: failure markers in output, [REVIEW-TASK]/[REVIEW-FIX] markers (recursion),
 * consultative subagent dispatches (analysis work — nothing to review), and
 * plan-complete injection for sessions outside the active boulder's lineage
 * (mirrors OMO's resolveActiveBoulderSession predicate) or with paused/abandoned status.
 * Uses node:fs appendFileSync (not Bun.write — spike showed reliability issues).
 */

const LOG_PATH = `${process.env.HOME}/.opencode/plugin/review-enforcer.log`
const LOG_MAX_BYTES = 10 * 1024 * 1024 // 10 MB before rotation
const DEBUG_ENABLED = process.env.OMO_REVIEW_ENFORCER_DEBUG === "1"

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

/** Boulder statuses that must never trigger the plan-complete injection. "completed" is allowed — the injection fires at the completion moment, before completeBoulder runs. */
const INACTIVE_BOULDER_STATUSES = new Set(["paused", "abandoned"])

const REVIEW_INSTRUCTION = `

---
🔍 **[REVIEW-ENFORCER]** Task completed successfully.

**ACTION REQUIRED**: Before proceeding to the next task, you MUST trigger a review of the work just completed.

Use your \`atlas-review-handler\` skill instructions:
1. Delegate a review task with \`[REVIEW-TASK]\` marker using \`task(category="unspecified-low", load_skills=["review-protocol"], run_in_background=true)\`
2. Wait for review results
3. If CRITICAL findings > 0, delegate a fix task with \`[REVIEW-FIX]\` marker
4. Maximum 2 review cycles, then proceed regardless

Refer to your loaded \`atlas-review-handler\` skill for the complete protocol.

🚦 **LIVE DEPLOYMENT GATE**

For config/plugin/runtime changes, verify evidence states before claiming working/deployed/active:

- [ ] repo_implemented — code changes committed and present in the branch
- [ ] tests_passed — automated or manual tests confirm correctness
- [ ] live_file_installed — built/config files copied/symlinked to their live locations
- [ ] active_config_registered — the running system references the new configuration
- [ ] runtime_loaded — the process/plugin/service has loaded without errors
- [ ] real_project_behavior_proven — observed in a real session, not just theoretical

If any live/runtime state is unverified, say \`Not verified live: [missing state]\` — do NOT claim working/deployed/active.
---
`

const PLAN_COMPLETION_INSTRUCTION = `

---
🏁 **[REVIEW-ENFORCER]** ALL PLAN TASKS COMPLETE — Full branch review required.

**ACTION REQUIRED**: The entire plan has been completed. Before finalizing, you MUST trigger a SYNCHRONOUS full-branch review.

1. Delegate a SYNCHRONOUS review task (run_in_background=false) with \`[REVIEW-TASK]\` marker
2. The review should cover ALL changes on this branch, not just the last task
3. Use \`task(category="unspecified-low", load_skills=["review-protocol"], run_in_background=false)\`
4. Process findings: CRITICAL → fix, WARNING → note, clean → finalize

**Evidence-state consolidation required**: Before finalizing, report the highest proven evidence state and link evidence paths. For each deliverable, explicitly state which of the six evidence states are verified: repo_implemented, tests_passed, live_file_installed, active_config_registered, runtime_loaded, real_project_behavior_proven. If any live/runtime state is unverified, say \`Not verified live: [missing state]\` — do NOT claim working/deployed/active.

**Closeout Summary**: Before finalizing, provide a concise closeout summary covering what this plan accomplished.

**TLDR of functionality created**:
- [1-3 bullets summarizing what the completed plan added/changed]

**Expected behavior**:
- [1-3 bullets describing what the user should now observe]

**User testing follow-up**:
- [1-5 concrete manual checks the user can perform after approval]

**Evidence caveat**: Whenever any live/runtime evidence state is missing, include \`Not verified live: [missing state]\`.

This closeout is response-only — do NOT write it to \`.sisyphus/\`, notepads, evidence files, or wisdom.

This is the final quality gate before plan completion.
---
`

/** Prevents plan completion review from triggering more than once per process lifetime */
let planCompletionTriggered = false

/** Deduplication: tracks already-processed callIDs. */
const processedCallIDs = new Set<string>()

/** Best-effort file log — never throws */
/** Rotate log when it exceeds size cap (keeps one backup .1) */
function rotateLogIfNeeded(): void {
	try {
		const stat = statSync(LOG_PATH)
		if (stat.size > LOG_MAX_BYTES) {
			const backup = `${LOG_PATH}.1`
			try { unlinkSync(backup) } catch { /* ignore */ }
			try {
				renameSync(LOG_PATH, backup)
			} catch {
				try { unlinkSync(LOG_PATH) } catch { /* ignore */ }
			}
		}
	} catch {
		/* file doesn't exist yet — nothing to rotate */
	}
}

/** Best-effort file log — never throws */
function log(level: string, message: string): void {
	if (level === "debug" && !DEBUG_ENABLED) return
	const timestamp = new Date().toISOString()
	const line = `[${timestamp}] [${level.toUpperCase()}] ${message}\n`
	try {
		mkdirSync(dirname(LOG_PATH), { recursive: true })
		rotateLogIfNeeded()
		appendFileSync(LOG_PATH, line)
	} catch {
		// intentionally swallowed
	}
}

function detectFailure(output: string): string | null {
	for (const marker of FAILURE_MARKERS) {
		if (output.includes(marker)) {
			return marker
		}
	}
	return null
}

function detectRecursion(output: string, argsStr: string): string | null {
	for (const marker of RECURSION_MARKERS) {
		if (output.includes(marker) || argsStr.includes(marker)) {
			return marker
		}
	}
	return null
}

function safeStringifyArgs(args: unknown): string {
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

function getPlanProgress(currentSessionId: string): { total: number; checked: number; complete: boolean } | null {
	const boulderPath = `${process.env.HOME}/.sisyphus/boulder.json`
	let boulderRaw: string
	try {
		boulderRaw = readFileSync(boulderPath, "utf-8")
	} catch {
		log("info", "getPlanProgress: boulder.json not found or unreadable")
		return null
	}

	let boulder: Record<string, unknown>
	try {
		boulder = JSON.parse(boulderRaw)
	} catch {
		log("info", "getPlanProgress: boulder.json contains invalid JSON")
		return null
	}

	const activePlan = boulder.active_plan
	if (typeof activePlan !== "string" || activePlan.length === 0) {
		log("info", "getPlanProgress: active_plan field missing or empty")
		return null
	}

	let planContent: string
	try {
		planContent = readFileSync(activePlan, "utf-8")
	} catch {
		log("info", `getPlanProgress: plan file not readable — ${activePlan}`)
		return null
	}

	const checkedRegex = /^- \[x\] /gm
	const uncheckedRegex = /^- \[ \] /gm

	const checkedMatches = planContent.match(checkedRegex)
	const uncheckedMatches = planContent.match(uncheckedRegex)

	const checked = checkedMatches ? checkedMatches.length : 0
	const unchecked = uncheckedMatches ? uncheckedMatches.length : 0
	const total = checked + unchecked

	if (total === 0) {
		log("info", "getPlanProgress: no checkboxes found in plan")
		return null
	}

	// Lineage gate (mirrors OMO resolve-active-boulder-session.ts): the plan-complete
	// injection may only fire for sessions inside the active boulder's session_ids.
	// Prevents a stale machine-global boulder.json from hijacking unrelated sessions.
	const sessionIdsRaw = boulder.session_ids
	const sessionIds = Array.isArray(sessionIdsRaw)
		? sessionIdsRaw.filter((id): id is string => typeof id === "string")
		: []
	if (!sessionOwnsBoulder(currentSessionId, sessionIds)) {
		log("info", `getPlanProgress: session ${currentSessionId || "<unknown>"} not in boulder lineage (${sessionIds.length} tracked ids) — plan-complete path disabled`)
		return null
	}
	if (!boulderStatusAllowsInjection(boulder.status)) {
		log("info", `getPlanProgress: boulder status "${String(boulder.status)}" blocks plan-complete injection`)
		return null
	}

	return { total, checked, complete: checked === total }
}

/** Run regression tests and return the output, or null on failure. Never throws. */
function runRegressionTests(projectPath: string): string | null {
	try {
		const output = execSync("bash tests/run_regressions.sh", {
			cwd: projectPath,
			encoding: "utf-8",
			timeout: 30000,
			stdio: ["ignore", "pipe", "pipe"],
		}).trim()
		log("info", `Regression tests ran successfully:\n${output}`)
		return output
	} catch (err) {
		const errMsg = err instanceof Error ? err.message : String(err)
		log("warn", `Regression tests could not run — ${errMsg}`)
		return null
	}
}

export const ReviewEnforcerPlugin: Plugin = async (ctx) => {
	const { client } = ctx

	const appLog = (level: "info" | "debug" | "warn" | "error", msg: string) =>
		client.app
			.log({ body: { service: "review-enforcer", level, message: msg } })
			.catch(() => {})

	log("info", "Plugin initialized")
	log("info", `Guards initialized: dedup=${processedCallIDs.size}, planComplete=${planCompletionTriggered}`)

	return {
		// output.output is MUTABLE — modifying it changes what the calling agent sees
		"tool.execute.after": async (input, output) => {
			if (input.tool !== "task") return

			try {
				// Dedup guard: skip already-processed callIDs
				const callID = input.callID ?? ""
				if (callID && processedCallIDs.has(callID)) {
					log("info", `SKIP (dedup) — callID=${callID} already processed`)
					return
				}

				const taskOutput = output.output ?? ""
				const argsStr = safeStringifyArgs(input.args)

				log("info", `Intercepted task completion — session=${input.sessionID}, callID=${input.callID}, outputLength=${taskOutput.length}`)
				// Consultative gate: analysis/review subagents produce no implementation work.
				if (isConsultativeDispatch(input.args)) {
					const reason = "task targets a consultative subagent (oracle/metis/momus/explore/librarian/multimodal-looker/document-writer) — no implementation work to review"
					log("info", `SKIP (consultative) — ${reason}`)
					appLog("debug", `review-enforcer: skipped — ${reason}`)
					return
				}

				// Positive success indicator — if present, task succeeded regardless of content
				if (!taskOutput.includes(SUCCESS_INDICATOR)) {
					const failureMarker = detectFailure(taskOutput)
					if (failureMarker) {
						const reason = `Task output contains failure marker: "${failureMarker}"`
						log("info", `SKIP (failure) — ${reason}`)
						appLog("debug", `review-enforcer: skipped — ${reason}`)
						return
					}
				}

				const recursionMarker = detectRecursion(taskOutput, argsStr)
				if (recursionMarker) {
					const reason = `Contains recursion marker: "${recursionMarker}"`
					log("info", `SKIP (recursion) — ${reason}`)
					appLog("debug", `review-enforcer: skipped — ${reason}`)
					return
				}

				// Timeout guard: measure elapsed time for getPlanProgress (sync I/O)
				const progressStart = Date.now()
			const progress = getPlanProgress(input.sessionID ?? "")
				const progressElapsed = Date.now() - progressStart
				if (progressElapsed > 5000) {
					log("warn", `getPlanProgress took ${progressElapsed}ms (>5s threshold) — result discarded`)
				}
				const safeProgress = progressElapsed > 5000 ? null : progress

				// Run regression tests for review context
				const projectPath = (ctx as { directory?: string }).directory ?? (process as any).cwd()
				const regressionResults = runRegressionTests(projectPath)
				const regressionSection = regressionResults
					? `\n## Regression Corpus Results\n${regressionResults}\n`
					: ""
				
				if (safeProgress?.complete && !planCompletionTriggered) {
					planCompletionTriggered = true
					output.output = taskOutput + regressionSection + PLAN_COMPLETION_INSTRUCTION
					log("info", `INJECT (plan-complete) — All ${safeProgress.total} tasks checked. Appended plan completion instructions.`)
					appLog("info", `review-enforcer: plan complete (${safeProgress.checked}/${safeProgress.total}) — injected full-branch review for callID=${input.callID}`)
					
					if (callID) processedCallIDs.add(callID)
					return
				}
				
				output.output = taskOutput + regressionSection + REVIEW_INSTRUCTION

				log("info", `INJECT — Appended review instructions (${REVIEW_INSTRUCTION.length} chars) to task output`)
				appLog("info", `review-enforcer: injected review instructions for task callID=${input.callID}`)

				if (callID) processedCallIDs.add(callID)
			} catch (err) {
				const errMsg = err instanceof Error ? err.message : String(err)
				log("error", `Unhandled error in hook — ${errMsg}`)
			}
		},
	}
}

export default ReviewEnforcerPlugin
