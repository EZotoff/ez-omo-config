import { describe, expect, test } from "bun:test"
import { truncateAtSentence } from "../src/text"

describe("truncateAtSentence", () => {
  test("short text passes through unchanged", () => {
    expect(truncateAtSentence("Approve all defaults.", 4000)).toBe("Approve all defaults.")
  })
  test("long multi-sentence text is cut at the last sentence boundary before the limit", () => {
    const sentence = "This is a complete sentence that ends here. "
    const text = sentence.repeat(200) // 10,800 chars
    const cut = truncateAtSentence(text, 4000)
    expect(cut.length).toBeLessThanOrEqual(4000)
    expect(cut.endsWith(".")).toBe(true)
    expect(cut).not.toMatch(/\w$/) // never ends mid-word
  })
  test("text with no sentence terminator before the limit cuts at whitespace with an ellipsis marker", () => {
    const text = "word ".repeat(2000)
    const cut = truncateAtSentence(text, 4000)
    expect(cut.length).toBeLessThanOrEqual(4000)
    expect(cut.endsWith("…")).toBe(true)
  })
  test("single uninterrupted run is hard-cut at the limit", () => {
    expect(truncateAtSentence("x".repeat(9000), 4000)).toBe(`${"x".repeat(3999)}…`)
  })
  test("boundary far below half the limit is not used (prefers whitespace over a tiny stub)", () => {
    const text = "One short sentence. " + "y".repeat(6000).replace(/y{5}/g, "yyyyy ")
    const cut = truncateAtSentence(text, 4000)
    expect(cut.length).toBeLessThanOrEqual(4000)
  })
})

test("card trim bounds: MAX_TEXT_CHARS keeps a full sentence under the cap", async () => {
  const { truncateAtSentence } = await import("../src/text")
  const question = "The requested outcome — a read-only triage of the meeting notes — was fully delivered: every item was categorized. The lab-branch question was directly answered: no, pulling upstream would not help. A third sentence follows here."
  const cut = truncateAtSentence(question, 200)
  expect(cut.length).toBeLessThanOrEqual(200)
  expect(cut.endsWith(".")).toBe(true)
})
