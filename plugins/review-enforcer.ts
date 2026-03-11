import { appendFileSync, mkdirSync, readFileSync } from "node:fs"
import { dirname } from "node:path"
import type { Plugin } from "@opencode-ai/plugin"

/**
 * Review Enforcer Plugin — intercepts task() completions via tool.execute.after
 * and injects review instructions into the output that Atlas sees.
 *
 * Skips: failure markers in output, [REVIEW-TASK]/[REVIEW-FIX] markers (recursion).
 * Uses node:fs appendFileSync (not Bun.write — spike showed reliability issues).
 */

const LOG_PATH = `${process.env.HOME}/.opencode/plugin/review-enforcer.log`

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

This is the final quality gate before plan completion.
---
`

/** Prevents plan completion review from triggering more than once per process lifetime */
let planCompletionTriggered = false

/** Deduplication: tracks already-processed callIDs. */
const processedCallIDs = new Set<string>()

/** Best-effort file log — never throws */
function log(level: string, message: string): void {
	const timestamp = new Date().toISOString()
	const line = `[${timestamp}] [${level.toUpperCase()}] ${message}\n`
	try {
		mkdirSync(dirname(LOG_PATH), { recursive: true })
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

function getPlanProgress(): { total: number; checked: number; complete: boolean } | null {
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

	return { total, checked, complete: checked === total }
}

export const ReviewEnforcerPlugin: Plugin = async (ctx) => {
	const { client } = ctx

	const appLog = (level: "info" | "debug" | "warn" | "error", msg: string) =>
		client.app
			.log({ body: { service: "review-enforcer", level, message: msg } })
			.catch(() => {})

	appLog("info", "Review enforcer plugin initialized (production)")
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
				const progress = getPlanProgress()
				const progressElapsed = Date.now() - progressStart
				if (progressElapsed > 5000) {
					log("warn", `getPlanProgress took ${progressElapsed}ms (>5s threshold) — result discarded`)
				}
				const safeProgress = progressElapsed > 5000 ? null : progress

				if (safeProgress !== null && safeProgress.complete && !planCompletionTriggered) {
					planCompletionTriggered = true
					output.output = taskOutput + PLAN_COMPLETION_INSTRUCTION
					log("info", `INJECT (plan-complete) — All ${safeProgress.total} tasks checked. Appended plan completion instructions.`)
					appLog("info", `review-enforcer: plan complete (${safeProgress.checked}/${safeProgress.total}) — injected full-branch review for callID=${input.callID}`)

					if (callID) processedCallIDs.add(callID)
					return
				}

				output.output = taskOutput + REVIEW_INSTRUCTION

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
