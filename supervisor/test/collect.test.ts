import { describe, expect, test } from "bun:test"
import {
  CollectBudget,
  CollectExecutor,
  DEFAULT_COLLECT_BOUNDS,
  collectEligible,
  detectProxies,
  type CollectBudgetGate,
  type CollectClient,
  type CollectEvent,
  type CollectRunner,
  type GatheredEvidence,
  type OpenTicketView,
} from "../src/collect"
import { parseDecision, runTickWithCollect, type CollectForkRequest, type InformationNeed } from "../src/tick"
import type { ReasoningAdapter } from "../src/adapter"
import type { AssembledContext } from "../src/assembler"
import type { Message, Session, Turn } from "../src/types"

const target: Turn = {
  sessionID: "ses-target",
  userMessageID: "u1",
  assistantMessageID: "a1",
  origin: "unknown",
  userText: "do the thing",
  assistantText: "done",
  transcript: "USER: do the thing\nASSISTANT: done",
}
const context: AssembledContext = { text: "L0 TARGET\nUSER: do the thing\nASSISTANT: done", estimatedTokens: 10, truncated: false }

const need = (over: Partial<InformationNeed> = {}): InformationNeed => ({
  question: "what happened in the sibling?",
  scope: "sessions",
  target: "ses-sib",
  why: "would change the call",
  expected_effect: "flip to ACCEPT",
  ...over,
})

const decisionJson = (over: Record<string, unknown> = {}): string =>
  JSON.stringify({
    action: "STEER",
    rationale: "conflict",
    citations: [{ session: "ses-target", messageID: "m1", quote: "q" }],
    confidence: 0.9,
    ...over,
  })

const scriptedAdapter = (responses: readonly string[]): ReasoningAdapter => {
  let index = 0
  return {
    complete: async () => {
      const response = responses[Math.min(index, responses.length - 1)]
      index += 1
      return response ?? ""
    },
  }
}

const gathered = (text = "SESSION ses-sib\nUSER (m2): earlier context"): GatheredEvidence => ({ text, tokens: 20, lookups: 1, empty: false })
const emptyEvidence: GatheredEvidence = { text: "", tokens: 0, lookups: 0, empty: true }

const stubRunner = (evidence: GatheredEvidence): { runner: CollectRunner; calls: InformationNeed[][] } => {
  const calls: InformationNeed[][] = []
  return {
    runner: {
      run: async (needs) => {
        calls.push([...needs])
        return evidence
      },
    },
    calls,
  }
}

const allowAll: CollectBudgetGate = { allow: () => true, record: () => {} }
const denyAll: CollectBudgetGate = { allow: () => false, record: () => {} }

const forkRequest = (over: Partial<CollectForkRequest> & { adapter: ReasoningAdapter }): CollectForkRequest => ({
  context,
  target,
  confidenceFloor: 0.6,
  root: "/root",
  executor: stubRunner(gathered()).runner,
  budget: allowAll,
  isIdle: async () => true,
  healthAmbiguous: false,
  hasSiblings: false,
  nowMs: () => 0,
  ...over,
})

describe("collectEligible gating matrix", () => {
  const base = { needs: [need()], healthAmbiguous: false, proxyFired: false, budgetAvailable: true }
  test("STEER collects by default", () => expect(collectEligible({ ...base, action: "STEER" })).toBe(true))
  test("ESCALATE collects by default", () => expect(collectEligible({ ...base, action: "ESCALATE" })).toBe(true))
  test("CONTINUE requires ambiguous health or a proxy", () => {
    expect(collectEligible({ ...base, action: "CONTINUE" })).toBe(false)
    expect(collectEligible({ ...base, action: "CONTINUE", healthAmbiguous: true })).toBe(true)
    expect(collectEligible({ ...base, action: "CONTINUE", proxyFired: true })).toBe(true)
  })
  test("ACCEPT and REFORMULATE require a proxy", () => {
    expect(collectEligible({ ...base, action: "ACCEPT" })).toBe(false)
    expect(collectEligible({ ...base, action: "ACCEPT", proxyFired: true })).toBe(true)
    expect(collectEligible({ ...base, action: "REFORMULATE" })).toBe(false)
    expect(collectEligible({ ...base, action: "REFORMULATE", proxyFired: true })).toBe(true)
  })
  test("ABSTAIN never collects", () => expect(collectEligible({ ...base, action: "ABSTAIN", proxyFired: true })).toBe(false))
  test("no named need never collects", () => expect(collectEligible({ ...base, action: "STEER", needs: [] })).toBe(false))
  test("budget exhaustion disables the fork", () => expect(collectEligible({ ...base, action: "STEER", budgetAvailable: false })).toBe(false))
})

describe("runTickWithCollect fork gating", () => {
  test("no information_need → no gather, tick1 is final", async () => {
    const { runner, calls } = stubRunner(gathered())
    const decision = await runTickWithCollect(forkRequest({ adapter: scriptedAdapter([decisionJson({ information_needs: [] })]), executor: runner }))
    expect(calls.length).toBe(0)
    expect(decision.action).toBe("STEER")
  })

  test("STEER + need → gather called once with ≤3 needs", async () => {
    const { runner, calls } = stubRunner(gathered())
    const decision = await runTickWithCollect(
      forkRequest({
        adapter: scriptedAdapter([decisionJson({ information_needs: [need()] }), decisionJson({ action: "STEER", evidence_effect: "confirmed" })]),
        executor: runner,
      }),
    )
    expect(calls.length).toBe(1)
    expect(calls[0]?.length ?? 0).toBeLessThanOrEqual(3)
    expect(decision.action).toBe("STEER")
  })

  test("ACCEPT + need without a proxy → no gather", async () => {
    const { runner, calls } = stubRunner(gathered())
    const decision = await runTickWithCollect(
      forkRequest({ adapter: scriptedAdapter([decisionJson({ action: "ACCEPT", information_needs: [need()] })]), executor: runner }),
    )
    expect(calls.length).toBe(0)
    expect(decision.action).toBe("ACCEPT")
  })

  test("budget exhausted → no gather, lean stands", async () => {
    const { runner, calls } = stubRunner(gathered())
    const events: CollectEvent[] = []
    const decision = await runTickWithCollect(
      forkRequest({
        adapter: scriptedAdapter([decisionJson({ information_needs: [need()] })]),
        executor: runner,
        budget: denyAll,
        onCollect: (event) => events.push(event),
      }),
    )
    expect(calls.length).toBe(0)
    expect(decision.action).toBe("STEER")
    expect(events[0]?.outcome).toBe("budget-blocked")
  })

  test("ESCALATE with a named need MUST collect before ticketing", async () => {
    const { runner, calls } = stubRunner(gathered())
    const decision = await runTickWithCollect(
      forkRequest({
        adapter: scriptedAdapter([
          decisionJson({ action: "ESCALATE", information_needs: [need({ scope: "ledger", target: "root" })] }),
          decisionJson({ action: "ESCALATE", evidence_effect: "confirmed" }),
        ]),
        executor: runner,
      }),
    )
    expect(calls.length).toBe(1)
    expect(decision.action).toBe("ESCALATE")
  })

  test("session busy after gather → discard, no tick2, no stale decision", async () => {
    const { runner, calls } = stubRunner(gathered())
    let completes = 0
    const adapter: ReasoningAdapter = {
      complete: async () => {
        completes += 1
        return decisionJson({ information_needs: [need()] })
      },
    }
    let idleCalls = 0
    const decision = await runTickWithCollect(
      forkRequest({
        adapter,
        executor: runner,
        isIdle: async () => {
          idleCalls += 1
          return idleCalls === 1
        },
      }),
    )
    expect(calls.length).toBe(1)
    expect(completes).toBe(1)
    expect(decision.action).toBe("ABSTAIN")
    expect(decision.rationale).toContain("resumed")
  })

  test("session busy before gather → no gather at all", async () => {
    const { runner, calls } = stubRunner(gathered())
    const decision = await runTickWithCollect(
      forkRequest({ adapter: scriptedAdapter([decisionJson({ information_needs: [need()] })]), executor: runner, isIdle: async () => false }),
    )
    expect(calls.length).toBe(0)
    expect(decision.action).toBe("ABSTAIN")
  })

  test("empty gather → lean stands, no tick2", async () => {
    const { runner } = stubRunner(emptyEvidence)
    let completes = 0
    const adapter: ReasoningAdapter = {
      complete: async () => {
        completes += 1
        return decisionJson({ information_needs: [need()] })
      },
    }
    const decision = await runTickWithCollect(forkRequest({ adapter, executor: runner }))
    expect(completes).toBe(1)
    expect(decision.action).toBe("STEER")
  })
})

describe("confirmation-bias guard", () => {
  test("tick2 prompt demands a confirmation statement and captures evidence_effect", async () => {
    const prompts: string[] = []
    const adapter: ReasoningAdapter = {
      complete: async (prompt) => {
        prompts.push(prompt)
        return prompts.length === 1
          ? decisionJson({ information_needs: [need()] })
          : decisionJson({ action: "ACCEPT", evidence_effect: "disconfirmed" })
      },
    }
    const events: CollectEvent[] = []
    const decision = await runTickWithCollect(
      forkRequest({ adapter, executor: stubRunner(gathered()).runner, onCollect: (event) => events.push(event) }),
    )
    expect(prompts[1]).toContain("CONFIRMATION CHECK")
    expect(prompts[1]).toContain("GATHERED EVIDENCE")
    expect(prompts[1]).toContain("YOUR PROVISIONAL LEAN: STEER")
    expect(decision.evidence_effect).toBe("disconfirmed")
    expect(events[0]?.changed).toBe(true)
    expect(events[0]?.evidenceEffect).toBe("disconfirmed")
  })
})

describe("parseDecision fork fields", () => {
  test("accepts singular information_need and canonicalizes to the array", () => {
    const d = parseDecision(
      JSON.stringify({
        action: "STEER",
        rationale: "x",
        citations: [{ session: "s", messageID: "m", quote: "q" }],
        confidence: 0.9,
        information_need: { question: "q", scope: "sessions", target: "ses-x", why: "w", expected_effect: "e" },
      }),
      0.6,
    )
    expect(d.information_needs.length).toBe(1)
    expect(d.information_needs[0]?.scope).toBe("sessions")
  })

  test("normalizes scope aliases (session_history → sessions, session_cards → cards)", () => {
    const d = parseDecision(
      JSON.stringify({
        action: "STEER",
        rationale: "x",
        citations: [{ session: "s", messageID: "m", quote: "q" }],
        confidence: 0.9,
        information_needs: [
          { question: "q", scope: "session_history", target: "ses-x", why: "w", expected_effect: "e" },
          { question: "q2", scope: "session_cards", target: "root", why: "w", expected_effect: "e" },
        ],
      }),
      0.6,
    )
    expect(d.information_needs.map((entry) => entry.scope)).toEqual(["sessions", "cards"])
  })

  test("caps needs at 3", () => {
    const needs = Array.from({ length: 5 }, (_, index) => ({ question: `q${index}`, scope: "sessions", target: "ses-x", why: "w", expected_effect: "e" }))
    const d = parseDecision(
      JSON.stringify({ action: "STEER", rationale: "x", citations: [{ session: "s", messageID: "m", quote: "q" }], confidence: 0.9, information_needs: needs }),
      0.6,
    )
    expect(d.information_needs.length).toBe(3)
  })

  test("provisional parse skips the confidence floor; final parse applies it", () => {
    const raw = JSON.stringify({
      action: "STEER",
      rationale: "x",
      citations: [{ session: "s", messageID: "m", quote: "q" }],
      confidence: 0.2,
      information_needs: [{ question: "q", scope: "sessions", target: "ses-x", why: "w", expected_effect: "e" }],
    })
    expect(parseDecision(raw, 0.6, { provisional: true }).action).toBe("STEER")
    expect(parseDecision(raw, 0.6).action).toBe("ABSTAIN")
  })

  test("rejects an unknown scope (corpus is not a primitive)", () => {
    const d = parseDecision(
      JSON.stringify({
        action: "STEER",
        rationale: "x",
        citations: [{ session: "s", messageID: "m", quote: "q" }],
        confidence: 0.9,
        information_needs: [{ question: "q", scope: "corpus", target: "ses-x", why: "w", expected_effect: "e" }],
      }),
      0.6,
    )
    expect(d.action).toBe("ABSTAIN")
  })

  test.each([
    ["CONFIRMED", "confirmed"],
    ["disconfirmed by the gathered evidence", "disconfirmed"],
    ["INCONCLUSIVE", "inconclusive"],
  ])("normalizes evidence_effect %s → %s", (raw, expected) => {
    const d = parseDecision(
      JSON.stringify({ action: "ESCALATE", rationale: "x", citations: [{ session: "s", messageID: "m", quote: "q" }], confidence: 0.9, evidence_effect: raw }),
      0.6,
    )
    expect(d.action).toBe("ESCALATE")
    expect(String(d.evidence_effect)).toBe(expected)
  })

  test("drops an unrecognized evidence_effect instead of abstaining", () => {
    const d = parseDecision(
      JSON.stringify({ action: "ESCALATE", rationale: "x", citations: [{ session: "s", messageID: "m", quote: "q" }], confidence: 0.9, evidence_effect: "banana" }),
      0.6,
    )
    expect(d.action).toBe("ESCALATE")
    expect(d.evidence_effect).toBeUndefined()
  })
})

describe("detectProxies", () => {
  test("P-empty fires on a degenerate target reply", () => {
    const signals = detectProxies({
      decision: parseDecision(decisionJson(), 0.6),
      target: { ...target, assistantText: "" },
      context,
      hasSiblings: false,
    })
    expect(signals.reasons).toContain("P-empty")
  })

  test("P-cross fires on a cross-session action with target-local citations", () => {
    const signals = detectProxies({ decision: parseDecision(decisionJson(), 0.6), target, context, hasSiblings: true })
    expect(signals.reasons).toContain("P-cross")
  })

  test("P-ref fires on a reference to an entity absent from context", () => {
    const signals = detectProxies({
      decision: parseDecision(decisionJson({ rationale: "as agreed earlier" }), 0.6),
      target,
      context,
      hasSiblings: false,
    })
    expect(signals.reasons).toContain("P-ref")
  })
})

describe("CollectExecutor bounds and primitives", () => {
  const message = (id: string, role: "user" | "assistant", text: string): Message => ({
    id,
    sessionID: "ses-sib",
    role,
    time: { created: 1, completed: 2 },
    parts: [{ id: `${id}-p`, messageID: id, type: "text", text }],
  })

  const stubClient = (options: { messages?: readonly Message[]; sessions?: readonly Session[] } = {}): CollectClient => ({
    listSessions: async () => options.sessions ?? [{ id: "ses-sib", directory: "/root" }],
    listAllSessions: async () => options.sessions ?? [{ id: "ses-sib", directory: "/root" }],
    listMessages: async () => options.messages ?? [],
  })

  const executor = (client: CollectClient, nowMs: () => number = () => 0): CollectExecutor =>
    new CollectExecutor({ client, root: "/root", ledgerRecords: () => [], openItems: () => [], nowMs })

  test("caps lookups at maxLookups", async () => {
    const client = stubClient({ messages: [message("u1", "user", "hello"), message("a1", "assistant", "world")] })
    const needs = [need({ target: "s1" }), need({ target: "s2" }), need({ target: "s3" }), need({ target: "s4" })]
    const result = await executor(client).run(needs, DEFAULT_COLLECT_BOUNDS)
    expect(result.lookups).toBeLessThanOrEqual(3)
  })

  test("caps gathered tokens at tokenCap", async () => {
    const client = stubClient({ messages: [message("u1", "user", "x".repeat(4000)), message("a1", "assistant", "y".repeat(4000))] })
    const result = await executor(client).run([need()], { ...DEFAULT_COLLECT_BOUNDS, tokenCap: 100 })
    expect(result.tokens).toBeLessThanOrEqual(100)
  })

  test("stops at the deadline", async () => {
    let now = 0
    const client: CollectClient = {
      listSessions: async () => [{ id: "ses-sib", directory: "/root" }],
      listAllSessions: async () => [{ id: "ses-sib", directory: "/root" }],
      listMessages: async () => {
        now += 40_000
        return [message("u1", "user", "hello"), message("a1", "assistant", "world")]
      },
    }
    const result = await executor(client, () => now).run([need({ target: "ses-sib" }), need({ target: "ses-sib" })], DEFAULT_COLLECT_BOUNDS)
    expect(result.lookups).toBe(1)
  })

  test("session_history projects U/A only — tool output never crosses the boundary", async () => {
    const messages: Message[] = [
      { id: "u1", sessionID: "ses-sib", role: "user", time: { created: 1 }, parts: [{ id: "p1", messageID: "u1", type: "text", text: "hello" }] },
      {
        id: "a1",
        sessionID: "ses-sib",
        role: "assistant",
        time: { created: 2, completed: 3 },
        parts: [
          { id: "p2", messageID: "a1", type: "tool", tool: "bash", state: { output: "SECRET TOOL OUTPUT" } },
          { id: "p3", messageID: "a1", type: "text", text: "world" },
        ],
      },
    ]
    const result = await executor(stubClient({ messages })).run([need({ scope: "sessions", target: "ses-sib" })], DEFAULT_COLLECT_BOUNDS)
    expect(result.text).toContain("hello")
    expect(result.text).toContain("world")
    expect(result.text).not.toContain("SECRET TOOL OUTPUT")
  })

  test("ledger_lookup surfaces past decisions and open tickets", async () => {
    const ledger = [
      { seq: 1, timestamp: "2026-09-20T00:00:00Z", type: "TICK_DECIDED" as const, payload: { sessionID: "ses-target", decision: { action: "CONTINUE", rationale: "waiting on worker" } }, prevHash: "GENESIS", hash: "a".repeat(64) },
    ]
    const openItems: OpenTicketView[] = [
      { id: "att_1", actionClass: "ESCALATE", question: "deploy to prod?", target: { sessionID: "ses-target" } },
    ]
    const exec = new CollectExecutor({
      client: stubClient(),
      root: "/root",
      ledgerRecords: () => ledger,
      openItems: () => openItems,
      nowMs: () => 0,
    })
    const result = await exec.run([need({ scope: "ledger", target: "ses-target" })], DEFAULT_COLLECT_BOUNDS)
    expect(result.text).toContain("CONTINUE")
    expect(result.text).toContain("OPEN TICKET att_1")
  })

  test("session_cards lists project sessions with titles", async () => {
    const sessions: Session[] = [
      { id: "ses-a", directory: "/root", title: "Alpha", timeUpdatedMs: 1000 },
      { id: "ses-b", directory: "/root", title: "Beta", timeUpdatedMs: 2000 },
    ]
    const result = await executor(stubClient({ sessions })).run([need({ scope: "cards", target: "root" })], DEFAULT_COLLECT_BOUNDS)
    expect(result.text).toContain("Alpha")
    expect(result.text).toContain("Beta")
  })
})

describe("CollectBudget", () => {
  test("enforces the per-root daily round cap", () => {
    const budget = new CollectBudget({ dailyRoundsPerRoot: 2, dailyTokensPerRoot: 1000, dailyRoundsPerSession: 5 })
    const now = Date.parse("2026-09-20T00:00:00Z")
    expect(budget.allow("/root", "s1", now)).toBe(true)
    budget.record("/root", "s1", 10, now)
    budget.record("/root", "s2", 10, now)
    expect(budget.allow("/root", "s3", now)).toBe(false)
  })

  test("enforces the per-session daily cap", () => {
    const budget = new CollectBudget({ dailyRoundsPerRoot: 10, dailyTokensPerRoot: 1000, dailyRoundsPerSession: 1 })
    const now = Date.parse("2026-09-20T00:00:00Z")
    budget.record("/root", "s1", 10, now)
    expect(budget.allow("/root", "s1", now)).toBe(false)
    expect(budget.allow("/root", "s2", now)).toBe(true)
  })

  test("resets on a new day", () => {
    const budget = new CollectBudget({ dailyRoundsPerRoot: 1, dailyTokensPerRoot: 1000, dailyRoundsPerSession: 5 })
    const day1 = Date.parse("2026-09-20T00:00:00Z")
    const day2 = Date.parse("2026-09-21T00:00:00Z")
    budget.record("/root", "s1", 10, day1)
    expect(budget.allow("/root", "s1", day1)).toBe(false)
    expect(budget.allow("/root", "s1", day2)).toBe(true)
  })
})
