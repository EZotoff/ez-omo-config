import { expect, test } from "bun:test"
import { parseDecision } from "../src/tick"
import { applyAttentionOverrides } from "../src/service"

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
