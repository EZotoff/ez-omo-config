import { describe, expect, test } from "bun:test"
import { parseDecision } from "../src/tick"

const valid = JSON.stringify({
  action: "STEER",
  target: "ses-a",
  rationale: "Sibling evidence conflicts",
  citations: [{ session: "ses-b", messageID: "msg-1", quote: "Redis breaks ordering" }],
  confidence: 0.9,
})

describe("parseDecision", () => {
  test("accepts strict valid JSON", () => expect(parseDecision(valid, 0.6).action).toBe("STEER"))
  test("normalizes safe GLM aliases for no-op decisions", () => {
    const raw = JSON.stringify({
      action: "none",
      target: null,
      rationale: "Benign turn; no intervention needed",
      citations: ["msg-1"],
      confidence: 0.98,
    })
    expect(parseDecision(raw, 0.6)).toMatchObject({ action: "ACCEPT", citations: [] })
  })
  test.each([
    ["malformed", "{"],
    ["missing citations", JSON.stringify({ action: "STEER", rationale: "x", confidence: 0.9 })],
    ["low confidence", JSON.stringify({ ...JSON.parse(valid), confidence: 0.2 })],
  ])("falls back to ABSTAIN for %s output", (_name, input) => {
    expect(parseDecision(input, 0.6).action).toBe("ABSTAIN")
  })
})
