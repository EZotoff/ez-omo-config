import { describe, expect, test } from "bun:test"
import { parseDecision, POLICY } from "../src/tick"

// Prompt-contract test for the judgment-policy rewrite (task 5).
// The POLICY constant is the supervisor's entire judgment surface; these
// assertions lock the operator-approved rules 6-11 and the size ceiling.

const estimateTokens = (text: string): number => Math.ceil(text.length / 4)

describe("POLICY rules 6-11 (intent, gloss, question-intent, deploy-default, memory)", () => {
  test("rule 6 — intent over literalism with the contradiction check", () => {
    expect(POLICY).toContain("Read operator messages for INTENT, not literal text")
    expect(POLICY).toContain("outweighs its literal wording")
    expect(POLICY).toContain("probable typo")
    expect(POLICY).toContain("Never CONTINUE on a reading that rests on a probable typo or self-contradiction")
  })

  test("rule 7 — continue-vs-proceed gloss and the in-flight guard", () => {
    expect(POLICY).toContain("KICK-START")
    expect(POLICY).toContain("APPROVE")
    expect(POLICY).toContain('"continue" means kick-start; "proceed" means approve')
    expect(POLICY).toContain("nothing is in flight")
  })

  test("rule 8 — question intent (thinking-prompt vs information request)", () => {
    expect(POLICY).toContain("thinking-prompt, not an info request")
  })

  test("rule 9 — deploy/credential default to ESCALATE", () => {
    expect(POLICY).toContain("Deployment, promote, prod-write, and credential decisions are ESCALATE by default")
    expect(POLICY).toContain("trust config marks deploys autonomous")
  })

  test("rule 10 — prior-turn usage as memory", () => {
    expect(POLICY).toContain("L1 TARGET HISTORY contains this session's prior turns")
    expect(POLICY).toContain("it is your memory")
  })

  test("rule 11 — self-memory and CONTINUE-then-STEER escalation", () => {
    expect(POLICY).toContain("Do not repeat a decision on the same unresolved cause")
    expect(POLICY).toContain("If you CONTINUEd last turn and the worker still has not delivered, STEER")
  })
})

describe("POLICY preserves the pre-existing contract", () => {
  test("rules 1-5 intact (least-intrusive, citations, confidence floor)", () => {
    expect(POLICY).toContain("CONTINUE means NO operator decision exists")
    expect(POLICY).toContain("Every non-ACCEPT/ABSTAIN action must cite specific messages")
    expect(POLICY).toContain("Prefer the least intrusive correct action")
    expect(POLICY).toContain("Calibrate confidence: 0.9+ only with clear textual evidence")
  })

  test("STRICT JSON contract unchanged", () => {
    expect(POLICY).toContain('Return STRICT JSON only: {"action": "ACCEPT|ABSTAIN|CONTINUE|STEER|REFORMULATE|ESCALATE"')
    expect(POLICY).toContain('"confidence": 0.0-1.0')
  })

  test("gate round-1 refinement — accept-completion and continue-decision-pends", () => {
    expect(POLICY).toContain("the requested outcome is DELIVERED in this reply")
    expect(POLICY).toContain("NOT complete: CONTINUE, never ACCEPT")
    expect(POLICY).toContain("a real decision — a choice between options, or authorization for consequential, out-of-scope, or destructive work — ESCALATE")
    expect(POLICY).toContain("APPROVE-CONTINUE, not ESCALATE")
    expect(POLICY).toContain("never nudge a finished exchange")
    expect(POLICY).toContain("the matter is SETTLED: do not re-ask it")
  })

  test("stays under the ~1.5k token ceiling", () => {
    expect(estimateTokens(POLICY)).toBeLessThan(1500)
  })
})

describe("CONTINUE mode contract", () => {
  const continueDecision = {
    action: "CONTINUE",
    rationale: "The idle worker needs a nudge",
    citations: [{ session: "ses-a", messageID: "msg-a", quote: "No reply" }],
    confidence: 0.9,
  }

  test.each([
    ["canonical kick-start", "kick_start", "kick_start"],
    ["hyphenated kick-start alias", "kick-start", "kick_start"],
    ["approve alias", "proceed", "approve"],
    ["explicit null", null, null],
  ])("normalizes %s", (_name, mode, expected) => {
    const decision = parseDecision(JSON.stringify({ ...continueDecision, mode }), 0.6)

    expect(decision).toMatchObject({ action: "CONTINUE", mode: expected })
  })

  test("keeps mode optional for old decisions", () => {
    const decision = parseDecision(JSON.stringify(continueDecision), 0.6)

    expect(decision.action).toBe("CONTINUE")
    expect("mode" in decision).toBe(false)
  })

  test("keeps the decision boundary strict", () => {
    const decision = parseDecision(JSON.stringify({ ...continueDecision, mode: "kick_start", extra: true }), 0.6)

    expect(decision.action).toBe("ABSTAIN")
  })

  test("declares the machine-consumed mode field without changing the action enum", () => {
    expect(POLICY).toContain('"mode": "kick_start|approve|null"')
    expect(POLICY).toContain("A CONTINUE must declare mode")
    expect(POLICY).toContain('"action": "ACCEPT|ABSTAIN|CONTINUE|STEER|REFORMULATE|ESCALATE"')
  })
})
