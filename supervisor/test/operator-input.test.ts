import { expect, test } from "bun:test"
import { parseDecision, type TickDecision } from "../src/tick"
import { applyAttentionOverrides } from "../src/service"
import { ACTIONS } from "../src/types"

const raw = (action: string, extra: Readonly<Record<string, unknown>> = {}) => JSON.stringify({
  action, rationale: "Choose A or B", citations: [], confidence: 0.9, ...extra,
})

test.each([undefined, null, false, "false", "garbage", 0])("defaults malformed/omitted operator ask %p to false without rejecting", (value) => {
  expect(parseDecision(raw("ACCEPT", { operator_input_requested: value }), 0.6)).toMatchObject({ action: "ACCEPT", operator_input_requested: false })
})

test.each([true, "true", "TRUE"]) ("normalizes an operator ask %p", (value) => {
  expect(parseDecision(raw("ACCEPT", { operator_input_requested: value }), 0.6)).toMatchObject({ action: "ACCEPT", operator_input_requested: true })
})

test.each(["ACCEPT", "ABSTAIN"])("overrides %s when the operator is explicitly asked and targeting is enabled", async (action) => {
  const decision = parseDecision(raw(action, { operator_input_requested: true }), 0.6)
  expect(await applyAttentionOverrides(decision, { adjudicateMachineOrigin: true })).toMatchObject({ action: "ESCALATE", rationale: "operator input requested: Choose A or B" })
})

test("flag off preserves the decision", async () => {
  const decision = parseDecision(raw("ACCEPT", { operator_input_requested: true }), 0.6)
  expect(await applyAttentionOverrides(decision, { adjudicateMachineOrigin: false })).toEqual(decision)
})

test("false does not override", async () => {
  const decision = parseDecision(raw("ACCEPT", { operator_input_requested: false }), 0.6)
  expect(await applyAttentionOverrides(decision, { adjudicateMachineOrigin: true })).toEqual(decision)
})

for (const action of ACTIONS) test(`post-judge action dispatch preserves ${action} unless it is a terminal operator ask`, async () => {
  const decision: TickDecision = { action, rationale: "Choose A or B", citations: [], confidence: 0.9, information_needs: [], operator_input_requested: true }
  const result = await applyAttentionOverrides(decision, { adjudicateMachineOrigin: true })
  expect(result.action).toBe(action === "ACCEPT" || action === "ABSTAIN" ? "ESCALATE" : action)
})

test("confidence gate preserves the structured ask for post-decision dispatch", async () => {
  const decision = parseDecision(raw("ACCEPT", { operator_input_requested: true, confidence: 0.2 }), 0.6)
  expect(await applyAttentionOverrides(decision, { adjudicateMachineOrigin: true })).toMatchObject({ action: "ESCALATE", operator_input_requested: true })
})
