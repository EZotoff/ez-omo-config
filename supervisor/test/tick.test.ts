import { describe, expect, test } from "bun:test"
import { parseDecision, runTick, POLICY } from "../src/tick"
import type { ReasoningAdapter } from "../src/adapter"
import type { AssembledContext } from "../src/assembler"
import type { Turn } from "../src/types"

const valid = JSON.stringify({
  action: "STEER",
  target: "ses-a",
  rationale: "Sibling evidence conflicts",
  citations: [{ session: "ses-b", messageID: "msg-1", quote: "Redis breaks ordering" }],
  confidence: 0.9,
})

describe("parseDecision", () => {
  test("accepts strict valid JSON", () => expect(parseDecision(valid, 0.6).action).toBe("STEER"))
  test.each([
    ["none", "none", null],
    ["approve", "approve", "msg-9"],
    ["allow", "allow", null],
    ["no_action", "no_action", null],
    ["answer", "answer", "msg-7"],
  ])("normalizes observed GLM no-op alias %s", (_name, action, target) => {
    const raw = JSON.stringify({
      action,
      target,
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


test("runTick fails closed to ABSTAIN when provider errors", async () => {
  const adapter: ReasoningAdapter = { complete: async () => { throw new Error("rate limited") } }
  const target: Turn = { sessionID: "ses-a", userMessageID: "u1", assistantMessageID: "a1", origin: "unknown", userText: "x", assistantText: "y", transcript: "USER: x\nASSISTANT: y" }
  const context: AssembledContext = { text: target.transcript, estimatedTokens: 5, truncated: false }
  const decision = await runTick({ adapter, target, context, confidenceFloor: 0.6 })
  expect(decision).toMatchObject({ action: "ABSTAIN", rationale: "reasoning adapter failed" })
})

describe("REFORMULATE covers foundational opacity (merged DEMAND_EXPLANATION)", () => {
  test.each([
    ["explain", "explain"],
    ["REQUEST_EXPLANATION", "request_explanation"],
    ["DEMAND_EXPLANATION", "demand_explanation"],
  ])("normalizes alias %s to REFORMULATE", (_name, action) => {
    const d = parseDecision(
      JSON.stringify({
        action,
        rationale: "foundations missing",
        citations: [{ session: "s", messageID: "m", quote: "q" }],
        confidence: 0.8,
      }),
      0.6,
    )
    expect(d.action).toBe("REFORMULATE")
  })

  test("still requires citations", () => {
    const d = parseDecision(
      JSON.stringify({ action: "explain", rationale: "x", confidence: 0.9 }),
      0.6,
    )
    expect(d.action).toBe("ABSTAIN")
  })

  test("policy carries the sufficiency test and the from-first-principles demand", () => {
    expect(POLICY).toContain("Sufficiency test before deciding")
    expect(POLICY).toContain("could a competent operator, seeing ONLY the supplied transcript")
    expect(POLICY).toContain("rebuilt from first principles")
    expect(POLICY).toContain("nothing from the session")
    expect(POLICY).not.toContain("DEMAND_EXPLANATION")
  })
})

test("uncertainty proxy synthesizes a need for high-stakes citations flagged unverified", () => {
  const raw = JSON.stringify({
    action: "STEER", target: null,
    rationale: "worker proceeds on a contradicted premise",
    citations: [{ session: "ses_other", messageID: "m1", quote: "unclear — the ledger mentions a proposal but no acceptance" }],
    confidence: 0.9,
  })
  const d = parseDecision(raw, 0.6)
  expect(d.information_needs?.length).toBe(1)
  expect(d.information_needs?.[0]?.scope).toBe("sessions")
})

test("uncertainty proxy does not fire on clean evidence or low-stakes actions", () => {
  const clean = JSON.stringify({ action: "STEER", rationale: "x", citations: [{ session: "s", messageID: "m", quote: "Redis was removed for ordering bugs" }], confidence: 0.9 })
  const low = JSON.stringify({ action: "ACCEPT", rationale: "x", citations: [{ session: "s", messageID: "m", quote: "unclear" }], confidence: 0.9 })
  expect(parseDecision(clean, 0.6).information_needs ?? []).toHaveLength(0)
  expect(parseDecision(low, 0.6).information_needs ?? []).toHaveLength(0)
})

test("proxy fires when model emits template-empty needs array", () => {
  const raw = JSON.stringify({ action: "ESCALATE", rationale: "x", citations: [{ session: "s", messageID: "m", quote: "not yet agreed on the migration" }], confidence: 0.9, information_needs: [] })
  expect(parseDecision(raw, 0.6).information_needs?.length).toBe(1)
})

/* --- SessionScheduler defer-not-drop (import lazily to avoid cycles in other tests) --- */
test("SessionScheduler defers throttled work instead of dropping it", async () => {
  const { SessionScheduler } = await import("../src/service")
  let ran = 0
  const now = { v: 0 }
  const sched = new SessionScheduler(1_000, () => now.v, async () => { ran += 1 })
  await sched.enqueue("ses-a")           // runs immediately (lastTickAt unset)
  sched.markTicked("ses-a")
  now.v = 500                            // next enqueue is throttled (500 < 1000)
  await sched.enqueue("ses-a")           // must DEFER, not drop
  now.v = 1_500                          // interval elapsed before the timer fires logic-wise;
  await new Promise((r) => setTimeout(r, 1_100))  // wait out the defer timer
  expect(ran).toBe(2)
})

test("decision prompt carries the kick-start evidence rule (audit 2026-09: K1/K3 false positives)", () => {
  expect(POLICY.includes("kick_start requires EVIDENCE OF UNFINISHED WORK")).toBe(true)
})
