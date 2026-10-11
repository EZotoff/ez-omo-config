// Service-level wiring for multi-genre comms (plan checkbox 6): the escalation
// proposal must surface the structured ask, write sites must forward
// instruction, and TICK_DECIDED must carry summary/instruction additively.
import { describe, expect, test } from "bun:test"
import { escalationQuestion, tickDecidedPayload, writeTextArgs } from "../src/service"
import { steerWriteText } from "../src/continue-writes"
import type { Decision, Turn } from "../src/types"

const turn: Turn = {
  sessionID: "ses_1",
  userMessageID: "msg_1",
  origin: "human",
  userText: "ship it",
  assistantText: "done",
  transcript: "ship it\ndone",
}

const summarized: Decision = {
  action: "ESCALATE",
  rationale: "three consecutive test failures on the migration path with no owner assigned",
  citations: [],
  confidence: 0.7,
  summary: { headline: "Migration tests failing", ask: "Should we roll back migration 004 or fix forward?", options: ["roll back", "fix forward"], recommendation: "fix forward" },
  instruction: "Pause the deploy and ask for a decision on migration 004.",
}

describe("escalationQuestion", () => {
  test("prefers the structured ask when summary is present", () => {
    expect(escalationQuestion(summarized)).toBe("Should we roll back migration 004 or fix forward?")
  })

  test("legacy summary-less decision falls back to a sentence-trimmed rationale capped at 140 chars, without throwing", () => {
    const first = "The migration path failed three consecutive test runs overnight and no owner has picked up the investigation yet."
    const legacy: Decision = { action: "ESCALATE", rationale: `${first} Meanwhile the deploy window closes in two hours and downstream consumers are already polling the broken endpoint.`, citations: [], confidence: 0.6 }
    const question = escalationQuestion(legacy)
    expect(question).toBe(first)
    expect(question.length).toBeLessThanOrEqual(140)
  })
})

describe("writeTextArgs", () => {
  test("carries instruction through when the decision has one", () => {
    expect(writeTextArgs(summarized)).toEqual({ instruction: "Pause the deploy and ask for a decision on migration 004.", rationale: summarized.rationale })
  })

  test("legacy instruction-less decision yields exactly the rationale, no phantom keys", () => {
    const legacy: Decision = { action: "STEER", rationale: "reconcile with A/13", citations: [], confidence: 0.8 }
    expect(writeTextArgs(legacy)).toEqual({ rationale: "reconcile with A/13" })
  })

  test("composes with steerWriteText so the write uses the instruction, not the rationale", () => {
    expect(steerWriteText(writeTextArgs(summarized))).toBe(`[supervisor] (steer) ${summarized.instruction}`)
  })
})

describe("tickDecidedPayload", () => {
  test("carries summary and instruction additively when present", () => {
    const payload = tickDecidedPayload(summarized, turn, "/root") as Record<string, unknown>
    expect(payload["summary"]).toBe(summarized.summary)
    expect(payload["instruction"]).toBe(summarized.instruction)
    expect(payload["decision"]).toBe(summarized)
  })

  test("legacy decision payload keeps its exact historical shape (no summary/instruction keys)", () => {
    const legacy: Decision = { action: "ACCEPT", rationale: "work is complete", citations: [], confidence: 0.9 }
    expect(tickDecidedPayload(legacy, turn, "/root")).toEqual({
      decision: legacy,
      root: "/root",
      sessionID: "ses_1",
      messageID: "msg_1",
    })
  })
})
