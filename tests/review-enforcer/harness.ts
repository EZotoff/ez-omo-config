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

console.log(`harness[${mode}]: ${passed} passed, ${failed} failed`)
process.exit(failed > 0 ? 1 : 0)
