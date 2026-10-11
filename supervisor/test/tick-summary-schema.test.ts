import { describe, expect, test } from "bun:test"
import { parseDecision } from "../src/tick"

const BASE = {
  action: "ESCALATE",
  rationale: "operator decision required: deploy to prod",
  citations: [{ session: "ses_1", messageID: "msg_1", quote: "shall I deploy to prod?" }],
  confidence: 0.8,
}

const raw = (extra: Record<string, unknown>): string => JSON.stringify({ ...BASE, ...extra })

describe("decision summary/instruction budget enforcement", () => {
  test("over-budget headline, ask, options, and instruction are trimmed, not rejected", () => {
    const decision = parseDecision(raw({
      summary: {
        // 72 chars: sentence boundary at index 30 keeps the trim well under 60.
        headline: `${"H".repeat(30)}. ${"H".repeat(40)}`,
        ask: `${"A".repeat(20)}. ${"A".repeat(150)}`,
        options: ["ship it", `${"L".repeat(30)} ${"L".repeat(30)}`, "roll back", "hold", "fifth", "sixth"],
        recommendation: `${"R".repeat(20)}. ${"R".repeat(120)}`,
      },
      instruction: `${"I".repeat(20)}. ${"I".repeat(320)}`,
    }), 0)

    expect(decision.action).toBe("ESCALATE") // not ABSTAIN — no rejection
    expect(decision.summary?.headline).toBeDefined()
    expect((decision.summary?.headline ?? "").length).toBeLessThanOrEqual(60)
    expect((decision.summary?.ask ?? "").length).toBeLessThanOrEqual(140)
    expect((decision.summary?.recommendation ?? "").length).toBeLessThanOrEqual(100)
    expect((decision.instruction ?? "").length).toBeLessThanOrEqual(300)
    // Options: clamped to first 4, each trimmed to 48.
    expect(decision.summary?.options?.length).toBe(4)
    expect(decision.summary?.options?.[0]).toBe("ship it")
    for (const option of decision.summary?.options ?? []) {
      expect(option.length).toBeLessThanOrEqual(48)
    }
  })

  test("absent summary and instruction parse as undefined", () => {
    const decision = parseDecision(raw({}), 0)
    expect(decision.action).toBe("ESCALATE")
    expect(decision.summary).toBeUndefined()
    expect(decision.instruction).toBeUndefined()
  })

  test("in-budget summary parses intact", () => {
    const summary = {
      headline: "Deploy 2.4 blocked on prod call",
      ask: "Approve the prod deploy?",
      options: ["ship it", "roll back"],
      recommendation: "ship it — CI is green and staged",
    }
    const decision = parseDecision(raw({ summary, instruction: "Fix the flaky test, then land." }), 0)
    expect(decision.summary).toEqual(summary)
    expect(decision.instruction).toBe("Fix the flaky test, then land.")
  })

  test("options over 8 words clamp to first 8 words, action intact", () => {
    const tenWords = "a b c d e f g h i j"
    const decision = parseDecision(raw({
      summary: {
        headline: "Deploy 2.4 blocked on prod call",
        ask: "Approve the prod deploy?",
        options: [tenWords, "roll back now please okay thanks again but maybe wait"],
      },
    }), 0)

    expect(decision.action).toBe("ESCALATE")
    expect(decision.summary?.options?.length).toBe(2)
    expect(decision.summary?.options?.[0]).toBe("a b c d e f g h")
    for (const option of decision.summary?.options ?? []) {
      expect(option.split(/\s+/).length).toBeLessThanOrEqual(8)
      expect(option.length).toBeLessThanOrEqual(48)
    }
  })

  test("ask missing a question mark gets one appended, action intact", () => {
    const decision = parseDecision(raw({
      summary: { headline: "Deploy 2.4 blocked on prod call", ask: "Approve the prod deploy" },
    }), 0)

    expect(decision.action).toBe("ESCALATE")
    expect(decision.summary?.ask).toBe("Approve the prod deploy?")
    expect((decision.summary?.ask ?? "").length).toBeLessThanOrEqual(140)
  })

})
