#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TMP_DIR="$(mktemp -d "$SCRIPT_DIR/.subagent-loop-guard.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

TEST_SCRIPT="$TMP_DIR/subagent-loop-guard.test.ts"

cat > "$TEST_SCRIPT" <<'TS'
import {
	createLoopGuardForTest,
	type LoopGuardBeforeOutput,
	type LoopGuardTestHarness,
} from "../../plugins/subagent-loop-guard.ts"

interface Scenario {
	readonly name: string
	readonly run: () => Promise<void> | void
}

let testsPassed = 0
let testsFailed = 0

function assert(condition: boolean, message: string): void {
	if (!condition) {
		throw new Error(message)
	}
}

function bashOutput(command: string): LoopGuardBeforeOutput {
	return { args: { command } }
}

async function beforeCall(
	guard: LoopGuardTestHarness,
	sessionID: string,
	callID: string,
	tool: string,
	command: string,
): Promise<LoopGuardBeforeOutput> {
	const output = bashOutput(command)
	await guard.before({ tool, sessionID, callID }, output)
	return output
}

async function afterCall(
	guard: LoopGuardTestHarness,
	sessionID: string,
	callID: string,
	tool: string,
	command: string,
): Promise<void> {
	await guard.after(
		{ tool, sessionID, callID, args: { command } },
		{ title: "done", output: "ok", metadata: {} },
	)
}

function wasBlocked(output: LoopGuardBeforeOutput): boolean {
	const command = output.args.command
	return typeof command === "string" && command.startsWith('echo "[loop-guard] blocked:')
}

const scenarios: readonly Scenario[] = [
	{
		name: "Rule A triggers after 31 same-tool calls in 50-call window",
		run: async () => {
			const guard = createLoopGuardForTest()
			let last = bashOutput("unset")
			for (let index = 0; index < 31; index++) {
				last = await beforeCall(guard, "session-a", `a-${index}`, "bash", "npm run build")
			}
			assert(wasBlocked(last), "31st same-tool call should be blocked by Rule A")
		},
	},
	{
		name: "Rule A does NOT trigger with only 29 same-tool calls in 50-call window",
		run: async () => {
			const guard = createLoopGuardForTest()
			let last = bashOutput("unset")
			for (let index = 0; index < 29; index++) {
				last = await beforeCall(guard, "session-a-low", `al-${index}`, "bash", "npm run build")
			}
			assert(!wasBlocked(last), "29 same-tool calls should stay below Rule A threshold")
		},
	},
	{
		name: "Rule B triggers when same tool is called 21 times with varying signatures in 30-call window",
		run: async () => {
			const guard = createLoopGuardForTest()
			let last = bashOutput("unset")
			for (let index = 0; index < 21; index++) {
				const command = index % 2 === 0 ? "npm run build" : "npm run test"
				last = await beforeCall(guard, "session-b", `b-${index}`, "bash", command)
			}
			assert(wasBlocked(last), "21 varying bash signatures should be blocked by Rule B")
		},
	},
	{
		name: "Rule B does NOT trigger with only 19 same-tool calls",
		run: async () => {
			const guard = createLoopGuardForTest()
			let last = bashOutput("unset")
			for (let index = 0; index < 19; index++) {
				const command = index % 2 === 0 ? "npm run build" : "npm run test"
				last = await beforeCall(guard, "session-b-low", `bl-${index}`, "bash", command)
			}
			assert(!wasBlocked(last), "19 varying bash signatures should stay below Rule B threshold")
		},
	},
	{
		name: "Rule B does NOT trigger when consecutive calls have identical signatures",
		run: async () => {
			const guard = createLoopGuardForTest({ env: { OMO_LOOP_GUARD_N_A: "100" } })
			let last = bashOutput("unset")
			for (let index = 0; index < 21; index++) {
				last = await beforeCall(guard, "session-b-repeat", `br-${index}`, "bash", "npm run test")
			}
			assert(!wasBlocked(last), "identical consecutive signatures should be left to OMO consecutive detection")
		},
	},
	{
		name: "Cooldown suppresses re-trigger within 60s",
		run: async () => {
			let now = 1_000
			const guard = createLoopGuardForTest({ now: () => now })
			let first = bashOutput("unset")
			for (let index = 0; index < 31; index++) {
				first = await beforeCall(guard, "session-cooldown", `cd-${index}`, "bash", "npm run build")
			}
			assert(wasBlocked(first), "first Rule A threshold crossing should be blocked")

			now += 1_000
			const second = await beforeCall(guard, "session-cooldown", "cd-second", "bash", "npm run build")
			assert(!wasBlocked(second), "same rule should be suppressed inside cooldown window")
		},
	},
	{
		name: "Different sessionIDs are tracked independently",
		run: async () => {
			const guard = createLoopGuardForTest()
			for (let index = 0; index < 30; index++) {
				await beforeCall(guard, "session-one", `one-${index}`, "bash", "npm run build")
			}
			const other = await beforeCall(guard, "session-two", "two-0", "bash", "npm run build")
			assert(!wasBlocked(other), "first call in a different session should not inherit session-one counts")
			const sessionOne = await beforeCall(guard, "session-one", "one-31", "bash", "npm run build")
			assert(wasBlocked(sessionOne), "original session should still trigger independently")
		},
	},
	{
		name: "Ring buffer evicts oldest entries beyond size 50",
		run: async () => {
			const guard = createLoopGuardForTest({ env: { OMO_LOOP_GUARD_N_A: "100", OMO_LOOP_GUARD_N_B: "100" } })
			for (let index = 0; index < 55; index++) {
				await afterCall(guard, "session-ring", `ring-${index}`, "bash", `cmd-${index}`)
			}
			const snapshot = guard.snapshot("session-ring")
			assert(snapshot !== null, "session-ring snapshot should exist")
			assert(snapshot.entries.length === 50, "ring buffer should retain exactly 50 entries")
			assert(snapshot.entries[0]?.callID === "ring-5", "ring buffer should evict the first five entries")
		},
	},
	{
		name: "OMO_LOOP_GUARD_DISABLE=1 makes plugin no-op",
		run: async () => {
			const guard = createLoopGuardForTest({ env: { OMO_LOOP_GUARD_DISABLE: "1" } })
			let last = bashOutput("unset")
			for (let index = 0; index < 40; index++) {
				last = await beforeCall(guard, "session-disabled", `disabled-${index}`, "bash", "npm run build")
			}
			assert(!wasBlocked(last), "disabled guard should not mutate bash commands")
			assert(guard.snapshot("session-disabled") === null, "disabled guard should not record session state")
		},
	},
	{
		name: "Internal error in hook does NOT propagate",
		run: async () => {
			const logs: string[] = []
			const guard = createLoopGuardForTest({ log: (_level, message) => logs.push(message) })
			guard.injectFaultOnce()
			await beforeCall(guard, "session-fail-open", "fail-0", "bash", "npm run build")
			assert(logs.some((message) => message.includes("fail-open")), "internal hook error should be logged")
		},
	},
]

for (const scenario of scenarios) {
	try {
		await scenario.run()
		console.log(`PASS: ${scenario.name}`)
		testsPassed += 1
	} catch (error) {
		const message = error instanceof Error ? error.message : String(error)
		console.error(`FAIL: ${scenario.name} — ${message}`)
		testsFailed += 1
	}
}

console.log(`Tests passed: ${testsPassed}`)
console.log(`Tests failed: ${testsFailed}`)

if (testsFailed > 0) {
	process.exit(1)
}
TS

cd "$REPO_ROOT"
bun "$TEST_SCRIPT"
