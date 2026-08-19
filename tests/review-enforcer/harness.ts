#!/usr/bin/env bun
/**
 * Behavioral harness for review-enforcer gating logic (regressions 014/015).
 *
 * Imports the plugin module and exercises the pure gating functions:
 *   - lineage mode:      normalizeSessionId / sessionOwnsBoulder / boulderStatusAllowsInjection
 *   - consultative mode: isConsultativeDispatch
 *
 * The module under test can be overridden via REVIEW_ENFORCER_MODULE (used by
 * kill-tests, which point it at a preserved pre-fix copy and expect failure).
 */
import { pathToFileURL } from "node:url"

const target = process.env.REVIEW_ENFORCER_MODULE
	? pathToFileURL(process.env.REVIEW_ENFORCER_MODULE).href
	: new URL("../../plugins/review-enforcer.ts", import.meta.url).href

const mod = (await import(target)) as {
	isConsultativeDispatch?: (args: unknown) => boolean
	normalizeSessionId?: (id: string) => string
	sessionOwnsBoulder?: (currentSessionId: string, sessionIds: readonly string[]) => boolean
	boulderStatusAllowsInjection?: (status: unknown) => boolean
}

let passed = 0
let failed = 0

function requireExport(name: keyof typeof mod): void {
	if (typeof mod[name] !== "function") {
		console.error(`FAIL: export "${name}" missing from module under test — gates not implemented?`)
		process.exit(1)
	}
}

function check(name: string, actual: boolean, expected: boolean): void {
	if (actual === expected) {
		passed++
	} else {
		failed++
		console.error(`FAIL: ${name} (expected ${expected}, got ${actual})`)
	}
}

const mode = process.argv[2] ?? "all"

if (mode === "all" || mode === "lineage") {
	requireExport("normalizeSessionId")
	requireExport("sessionOwnsBoulder")
	requireExport("boulderStatusAllowsInjection")
	const normalizeSessionId = mod.normalizeSessionId!
	const sessionOwnsBoulder = mod.sessionOwnsBoulder!
	const boulderStatusAllowsInjection = mod.boulderStatusAllowsInjection!

	// --- normalizeSessionId: OMO parity (bare -> "opencode:" prefix, idempotent)
	check("normalize bare id adds prefix", normalizeSessionId("ses_A") === "opencode:ses_A", true)
	check("normalize prefixed id is idempotent", normalizeSessionId("opencode:ses_A") === "opencode:ses_A", true)

	// --- sessionOwnsBoulder: lineage matching across legacy/prefixed formats
	check("legacy bare id owns session", sessionOwnsBoulder("ses_A", ["ses_A"]), true)
	check("prefixed lineage id owns bare session", sessionOwnsBoulder("ses_A", ["opencode:ses_A"]), true)
	check("bare lineage id owns prefixed session", sessionOwnsBoulder("opencode:ses_A", ["ses_A"]), true)
	check("prefixed both sides matches", sessionOwnsBoulder("opencode:ses_A", ["opencode:ses_A"]), true)
	check("unrelated session does not own plan", sessionOwnsBoulder("ses_B", ["ses_A", "ses_C"]), false)
	check("empty lineage never owns plan", sessionOwnsBoulder("ses_A", []), false)

	// --- exact 2026-08-16 misfire shape: stale March boulder.json (real ids) vs debate session
	const marchBoulderIds = ["ses_31195e75affecSPDKlaTn6fuPL", "ses_31197c123ffeF30FH5xJOdaXil"]
	check("REPRO: debate session does not own stale March boulder", sessionOwnsBoulder("ses_ff594298bffeWXBu7AhWFcF4jk", marchBoulderIds), false)
	check("REPRO: recorded boulder session does own it", sessionOwnsBoulder("ses_31195e75affecSPDKlaTn6fuPL", marchBoulderIds), true)

	// --- boulderStatusAllowsInjection: paused/abandoned block, everything else allows
	check("missing status allows injection (legacy mirror)", boulderStatusAllowsInjection(undefined), true)
	check("non-string status allows injection", boulderStatusAllowsInjection(42), true)
	check("active status allows injection", boulderStatusAllowsInjection("active"), true)
	check("completed status allows injection (fires at completion moment)", boulderStatusAllowsInjection("completed"), true)
	check("paused status blocks injection", boulderStatusAllowsInjection("paused"), false)
	check("abandoned status blocks injection", boulderStatusAllowsInjection("abandoned"), false)
}

if (mode === "all" || mode === "consultative") {
	requireExport("isConsultativeDispatch")
	const isConsultativeDispatch = mod.isConsultativeDispatch!

	// --- every consultative subagent type is skipped
	for (const t of ["oracle", "metis", "momus", "explore", "librarian", "multimodal-looker", "document-writer"]) {
		check(`subagent_type=${t} is consultative`, isConsultativeDispatch({ subagent_type: t, prompt: "x" }), true)
	}

	// --- implementation dispatches are NOT skipped (conservative default-fire)
	check("subagent_type=build is not consultative", isConsultativeDispatch({ subagent_type: "build" }), false)
	check("subagent_type=sisyphus is not consultative", isConsultativeDispatch({ subagent_type: "sisyphus" }), false)
	check("category=quick is not consultative (implementation category)", isConsultativeDispatch({ category: "quick", prompt: "x" }), false)
	check("absent type field defaults to fire", isConsultativeDispatch({ prompt: "do work" }), false)

	// --- alternate arg shapes
	check("legacy agent field honored", isConsultativeDispatch({ agent: "oracle" }), true)
	check("JSON-string args parsed", isConsultativeDispatch(JSON.stringify({ subagent_type: "oracle" })), true)
	check("garbage string args are not consultative", isConsultativeDispatch("not json {"), false)
	check("null args are not consultative", isConsultativeDispatch(null), false)
	check("undefined args are not consultative", isConsultativeDispatch(undefined), false)

	// --- exact 2026-08-16 misfire shape: debate Stage-1 Oracle dispatch
	check(
		"REPRO: debate Oracle dispatch is consultative",
		isConsultativeDispatch({ subagent_type: "oracle", run_in_background: true, description: "Debate Stage 1", prompt: "Propose the full edit..." }),
		true,
	)
}

if (mode === "all" || mode === "abort") {
	requireExport("isAbortStub")
	requireExport("isDegenerateOutput")
	requireExport("detectRecursion")
	requireExport("isConsultativeDispatch")
	const isAbortStub = mod.isAbortStub!
	const isDegenerateOutput = mod.isDegenerateOutput!
	const detectRecursion = mod.detectRecursion!
	const isConsultativeDispatch = mod.isConsultativeDispatch!

	// --- isAbortStub: OMO sync-task abort stubs are failures, not completions
	const stub = 'Aborted\n\nto continue: task(task_id="ses_fe702ddb7ffeBrOa63ARedL2QR", load_skills=[], run_in_background=false, prompt="...")'
	check("REPRO: exact 2026-08-19 abort stub detected", isAbortStub(stub), true)
	check("bare Aborted prefix detected", isAbortStub("Aborted\n\nsomething else"), true)
	check("continuation-stub signature detected mid-output", isAbortStub("Prefix text. to continue: task(task_id=\"ses_x\")"), true)
	check("normal completion is not an abort stub", isAbortStub("## SUBAGENT WORK COMPLETED\nFixed the parser bug and added tests."), false)
	check("mid-text 'Aborted' mention is not a stub", isAbortStub("The npm install printed 'Aborted!' to stderr but we retried and it succeeded."), false)

	// --- isDegenerateOutput: near-empty outputs without the success indicator carry no reviewable work
	check("REPRO: 123-char stub is degenerate", isDegenerateOutput(stub.slice(0, 123)), true)
	check("short output WITH success indicator is not degenerate", isDegenerateOutput("## SUBAGENT WORK COMPLETED"), false)
	check("substantial output is not degenerate", isDegenerateOutput("x".repeat(500)), false)
	check("empty output is degenerate", isDegenerateOutput(""), true)

	// --- [DEBATE] marker joins the recursion/skip markers
	check("[DEBATE] marker in args skips", detectRecursion("", JSON.stringify({ category: "artistry", prompt: "[DEBATE] Judge this design..." })) !== null, true)
	check("[REVIEW-TASK] marker still skips", detectRecursion("", JSON.stringify({ prompt: "[REVIEW-TASK] review" })) !== null, true)
	check("unmarked args do not skip", detectRecursion("", JSON.stringify({ category: "artistry", prompt: "Judge this design" })) === null, true)

	// --- category gate: mephistopheles is consultative; judge categories rely on [DEBATE] marker
	check("REPRO: category=mephistopheles is consultative", isConsultativeDispatch({ category: "mephistopheles", prompt: "CRITIQUE STAGE..." }), true)
	check("category=artistry alone is NOT skipped (needs [DEBATE] marker)", isConsultativeDispatch({ category: "artistry", prompt: "Review this design" }), false)
	check("category=writing alone is NOT skipped", isConsultativeDispatch({ category: "writing", prompt: "Review this design" }), false)
	check("category=ultrabrain alone is NOT skipped", isConsultativeDispatch({ category: "ultrabrain", prompt: "Review this design" }), false)
}

console.log(`harness[${mode}]: ${passed} passed, ${failed} failed`)
process.exit(failed > 0 ? 1 : 0)
