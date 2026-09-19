import { describe, expect, test } from "bun:test"
import { assembleContext, defaultTierBudgets, type AssembleInput, type SiblingView } from "../src/assembler"
import type { Turn } from "../src/types"

const NOW = Date.parse("2026-09-20T12:00:00.000Z")
const HOUR = 3_600_000
const DAY = 86_400_000

const text = (tokens: number): string => "x".repeat(tokens * 4)

const turn = (sessionID: string, marker: string, tokens = 4): Turn => ({
  sessionID,
  userMessageID: `u-${marker}`,
  assistantMessageID: `a-${marker}`,
  origin: "human",
  userText: `user-${marker}`,
  assistantText: `assistant-${marker}`,
  transcript: `${marker} ${text(tokens)}`,
})

const target: Turn = {
  sessionID: "ses-target",
  userMessageID: "u-target",
  assistantMessageID: "a-target",
  origin: "human",
  userText: "target user",
  assistantText: "target assistant",
  transcript: "L0 target transcript",
}

const base: Omit<AssembleInput, "siblings" | "siblingChanges" | "selfMemory" | "tierBudgets"> = {
  target,
  targetHistory: [],
  targetHistoryCapPairs: 50,
  siblingTurnWindow: 3,
  tokenBudget: 40_000,
  nowMs: NOW,
}

describe("assembler v2 recency tiers", () => {
  test("assigns HOT/WARM/COOL/COLD by age and renders uniform depth with title prefixes", () => {
    const sibling = (sessionID: string, title: string, ageMs: number, count: number): SiblingView => ({
      sessionID,
      title,
      lastActivityMs: NOW - ageMs,
      turns: Array.from({ length: count }, (_, index) => turn(sessionID, `${sessionID}-${String(index + 1).padStart(2, "0")}`)),
    })
    const result = assembleContext({
      ...base,
      siblings: [
        sibling("ses-hot", "Hot strand", 30 * 60_000, 10),
        sibling("ses-warm", "Warm strand", 3 * HOUR, 10),
        sibling("ses-cool", "Cool strand", 3 * DAY, 10),
        sibling("ses-cold", "Cold strand", 10 * DAY, 10),
      ],
    })
    expect(result.text).toContain("[HOT] Hot strand")
    expect(result.text).toContain("[WARM] Warm strand")
    expect(result.text).toContain("[COOL] Cool strand")
    expect(result.text).toContain("[COLD] Cold strand")
    // HOT: last 8 pairs (03..10), oldest two dropped.
    expect(result.text).toContain("ses-hot-03")
    expect(result.text).toContain("ses-hot-10")
    expect(result.text).not.toContain("ses-hot-01")
    expect(result.text).not.toContain("ses-hot-02")
    // WARM: last 3 pairs (08..10).
    expect(result.text).toContain("ses-warm-08")
    expect(result.text).toContain("ses-warm-10")
    expect(result.text).not.toContain("ses-warm-07")
    // COOL: last assistant text only.
    expect(result.text).toContain("ASSISTANT: assistant-ses-cool-10")
    expect(result.text).not.toContain("ses-cool-01")
    // COLD: title + age only.
    expect(result.text).not.toContain("ses-cold-01")
    expect(result.text).not.toContain("assistant-ses-cold")
  })

  test("caps target history at 50 pairs, dropping the oldest", () => {
    const history = Array.from({ length: 60 }, (_, index) => turn("ses-target", `h-${String(index + 1).padStart(2, "0")}`))
    const result = assembleContext({ ...base, targetHistory: history })
    expect(result.text).toContain("h-60")
    expect(result.text).toContain("h-11")
    expect(result.text).not.toContain("h-10")
    expect(result.text).not.toContain("h-01")
  })

  test("degrades COLD→COOL→WARM→L1-oldest instead of ABSTAIN-by-truncation", () => {
    const bigTarget: Turn = { ...target, transcript: text(20_000) }
    const history = Array.from({ length: 15 }, (_, index) => turn("ses-target", `h-${String(index + 1).padStart(2, "0")}`, 1_000))
    const hot: SiblingView = { sessionID: "ses-hot", title: "Hot", lastActivityMs: NOW - 30 * 60_000, turns: Array.from({ length: 8 }, (_, index) => turn("ses-hot", `hot-${index}`, 1_000)) }
    const warm: SiblingView = { sessionID: "ses-warm", title: "Warm", lastActivityMs: NOW - 3 * HOUR, turns: Array.from({ length: 3 }, (_, index) => turn("ses-warm", `warm-${index}`, 2_000)) }
    const coolTurn: Turn = { ...turn("ses-cool", "cool-0"), assistantText: text(4_000) }
    const cool: SiblingView = { sessionID: "ses-cool", title: "Cool", lastActivityMs: NOW - 3 * DAY, turns: [coolTurn] }
    const cold: SiblingView = { sessionID: "ses-cold", title: "Cold", lastActivityMs: NOW - 10 * DAY, turns: [turn("ses-cold", "cold-0")] }
    const result = assembleContext({ ...base, target: bigTarget, targetHistory: history, siblings: [hot, warm, cool, cold] })
    expect(result.truncated).toBe(false)
    expect(result.degraded).toEqual(["COLD", "COOL", "WARM", "L1-OLDEST"])
    expect(result.text).not.toContain("[COLD]")
    expect(result.text).not.toContain("[COOL]")
    expect(result.text).not.toContain("[WARM]")
    expect(result.text).toContain("[HOT]")
  })

  test("ABSTAIN-by-truncation only when L0 alone overflows", () => {
    const huge: Turn = { ...target, transcript: text(50_000) }
    const result = assembleContext({ ...base, target: huge })
    expect(result.truncated).toBe(true)
    expect(result.degraded).toEqual([])
  })

  test("keeps the L3 self-memory block in the tiered path", () => {
    const result = assembleContext({
      ...base,
      selfMemory: { decisions: [{ action: "CONTINUE", rationale: "go-ahead", decidedAtMs: NOW - 60_000 }], openItems: [], nowMs: NOW },
    })
    expect(result.text).toContain("L3 SELF-MEMORY")
    expect(result.text).toContain("CONTINUE (1m ago) — go-ahead")
  })

  test("legacy siblingChanges still renders flat siblings", () => {
    const result = assembleContext({ ...base, siblingChanges: { "ses-legacy": [turn("ses-legacy", "legacy-0")] } })
    expect(result.text).toContain("SIBLING ses-legacy")
  })

  test("default tier budgets match the 40k allocation", () => {
    expect(defaultTierBudgets(40_000)).toEqual({ targetHistory: 15_000, hot: 8_000, warm: 6_000, cool: 4_000, cold: 2_000 })
  })
})
