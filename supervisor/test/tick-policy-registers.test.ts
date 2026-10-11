import { describe, expect, test } from "bun:test"
import { POLICY } from "../src/tick"

// Prompt-contract test for the multi-genre comms amendment (task 2):
// the POLICY must teach the model the two output registers and the
// extended STRICT JSON template (budgets mirror summarySchema in tick.ts).

describe("POLICY register rules 16-17 (operator/worker genre)", () => {
  test("rule 16 — OPERATOR REGISTER declares field budgets and bans deliberation", () => {
    expect(POLICY).toContain("OPERATOR REGISTER")
    expect(POLICY).toContain("state of the world")
    expect(POLICY).toContain("ending in \"?\"")
    expect(POLICY).toContain("only for DECISION/APPROVAL")
    expect(POLICY).toContain("one-clause why")
    expect(POLICY).toContain("Never use first-person deliberation")
    expect(POLICY).toContain("confirmation-loop vocabulary")
    expect(POLICY).toContain("quote the worker's actual pending ask, cleaned")
    expect(POLICY).toContain("State facts, not process")
  })

  test("rule 17 — WORKER REGISTER requires an imperative instruction on STEER/REFORMULATE", () => {
    expect(POLICY).toContain("WORKER REGISTER")
    expect(POLICY).toContain("imperative")
    expect(POLICY).toContain("citing the conflicting fact")
    expect(POLICY).toContain("required when action is STEER or REFORMULATE")
  })

  test("STRICT JSON template carries summary and instruction", () => {
    expect(POLICY).toContain(
      '"summary": {"headline": "...", "ask": "...", "options": ["..."], "recommendation": "..."}, "instruction": "..."',
    )
  })
})
