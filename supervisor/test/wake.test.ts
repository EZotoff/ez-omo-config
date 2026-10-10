import { expect, test } from "bun:test"
import { parseDecision } from "../src/tick"
import { applyAttentionOverrides } from "../src/service"
import { verifyWakeHandle, type WakeProbe } from "../src/wake"

const decision = (wake_handle: unknown, action = "ABSTAIN") => parseDecision(JSON.stringify({
  action, rationale: "Watcher will resume this work", citations: [], confidence: 0.9, wake_handle,
}), 0.6)

test("wake handles normalize without rejecting an otherwise valid decision", () => {
  expect(decision({ kind: "SYSTEMD_UNIT", ref: "watcher.service" })).toMatchObject({ wake_handle: { kind: "systemd-unit", ref: "watcher.service" } })
  for (const value of [undefined, null, "bogus", { kind: "bogus", ref: "x" }, { kind: "process", ref: "" }]) {
    expect(decision(value)).toMatchObject({ action: "ABSTAIN", rationale: "Watcher will resume this work" })
  }
})

test("dead ABSTAIN wake handle escalates only with the wake flag on", async () => {
  const judged = decision({ kind: "systemd-unit", ref: "dead.service" })
  expect(await applyAttentionOverrides(judged, { adjudicateMachineOrigin: true, verifyWake: true, wakeVerifier: async () => false })).toMatchObject({ action: "ESCALATE", rationale: "claimed wake handle dead.service not found" })
  expect(await applyAttentionOverrides(judged, { adjudicateMachineOrigin: true, verifyWake: false, wakeVerifier: async () => false })).toEqual(judged)
})

test("verified ABSTAIN wake handle stays ABSTAIN", async () => {
  const judged = decision({ kind: "process", ref: "123" })
  expect(await applyAttentionOverrides(judged, { adjudicateMachineOrigin: true, verifyWake: true, wakeVerifier: async () => true })).toEqual(judged)
})

test.each(["systemd-unit", "timer", "process", "none"] as const)("probes %s read-only with list-form arguments and a 2s timeout", async (kind) => {
  const calls: { command: string; args: readonly string[]; timeout: number }[] = []
  const probe: WakeProbe = async (command, args, timeout) => { calls.push({ command, args, timeout }); return false }
  const ref = "watcher; touch /tmp/never"
  expect(await verifyWakeHandle({ kind, ref }, probe)).toBe(kind === "none")
  if (kind !== "none") {
    expect(calls).toEqual([{ command: kind === "process" ? "pgrep" : "systemctl", args: kind === "process" ? ["-f", "--", ref] : ["--user", "is-active", "--", ref], timeout: 2_000 }])
  } else expect(calls).toHaveLength(0)
})

test("live and missing numeric process handles use an existence probe", async () => {
  expect(await verifyWakeHandle({ kind: "process", ref: String(process.pid) })).toBe(true)
  expect(await verifyWakeHandle({ kind: "process", ref: "2147483647" })).toBe(false)
})

test("active units and process patterns honor probe success", async () => {
  for (const kind of ["systemd-unit", "timer", "process"] as const) {
    expect(await verifyWakeHandle({ kind, ref: "watcher" }, async () => true)).toBe(true)
  }
})

test("ACCEPT never invokes the wake verifier and operator asks take precedence", async () => {
  let probes = 0
  const wakeVerifier = async () => { probes += 1; return false }
  const accepted = decision({ kind: "process", ref: "123" }, "ACCEPT")
  expect(await applyAttentionOverrides(accepted, { adjudicateMachineOrigin: true, verifyWake: true, wakeVerifier })).toEqual(accepted)
  const asked = { ...accepted, action: "ABSTAIN" as const, operator_input_requested: true }
  expect(await applyAttentionOverrides(asked, { adjudicateMachineOrigin: true, verifyWake: true, wakeVerifier })).toMatchObject({ action: "ESCALATE", rationale: `operator input requested: ${asked.rationale}` })
  expect(probes).toBe(0)
})
