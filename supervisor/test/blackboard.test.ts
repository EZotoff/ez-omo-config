import { describe, expect, test } from "bun:test"
import { mkdtemp, rm } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { Blackboard, GLOBAL_ENTRY_CAP, parseTickDecided } from "../src/blackboard"
import { revalidate, type RevalidationSources } from "../src/queue"
import type { AttentionQueueItem } from "../src/types"
import { ACTIONS, type LedgerRecord } from "../src/types"

const T0 = "2026-09-20T12:00:00.000Z"
const at = (offsetMs: number): string => new Date(Date.parse(T0) + offsetMs).toISOString()
const HOUR = 60 * 60 * 1000

async function openBlackboard(appendLedger = false): Promise<{ board: Blackboard; dir: string; records: LedgerRecord[] }> {
  const dir = await mkdtemp(join(tmpdir(), "blackboard-"))
  const records: LedgerRecord[] = []
  if (!appendLedger) {
    const board = await Blackboard.open({ path: join(dir, "blackboard.json") })
    return { board, dir, records }
  }
  const { Ledger } = await import("../src/ledger")
  let ledger = await Ledger.open(join(dir, "ledger.jsonl"))
  const board = await Blackboard.open({
    path: join(dir, "blackboard.json"),
    append: async (type, payload) => {
      ledger = await ledger.append(type, payload)
      records.push(...ledger.records.slice(records.length))
    },
  })
  return { board, dir, records }
}

const allTrueSources = (overrides?: Partial<RevalidationSources>): RevalidationSources => ({
  targetExists: () => true,
  targetIdle: () => true,
  latestMessageID: () => "msg_last",
  targetTurnAborted: () => false,
  ticketOpen: () => true,
  blackboardFactActive: () => true,
  canonicalItemFor: () => undefined,
  answeredElsewhere: () => undefined,
  approvalRequired: () => false,
  modePermits: () => true,
  citationsAdmissible: () => true,
  ...overrides,
})

const queueItem = (): AttentionQueueItem => ({
  schemaVersion: 1,
  id: "att_test1",
  version: 1,
  decisionKey: "root|ses_1|ESCALATE|DECISION|deploy-now",
  kind: "decision",
  origin: {
    tickID: "tick_1",
    ledgerSeq: 1,
    decision: { action: "ESCALATE", rationale: "deploy blocked", citations: [], confidence: 0.9 },
    citations: [],
    informationNeeds: [],
    contextDigest: "d",
  },
  target: { root: "/root", sessionID: "ses_1", userMessageID: "msg_u1", assistantMessageID: "msg_a1" },
  actionClass: "ESCALATE",
  escalationKind: "DECISION",
  question: "Hold the deploy?",
  rationale: "deploy touches prod",
  priority: { stakes: 3, urgency: 3, confidence: 0.9, freshness: 1, createdAt: T0 },
  premises: [{ id: "p1", kind: "no-newer-turn", sessionID: "ses_1", latestMessageID: "msg_last", observedAt: T0 }],
  relatedItemIDs: [],
  lifecycle: [{ state: "proposed", at: T0, actor: "tick" }],
  poisonCount: 0,
})

describe("blackboard", () => {
  test("TTL expiry evicts facts from the active view", async () => {
    const { board, dir } = await openBlackboard()
    try {
      const { fact } = await board.writeFact({ root: "/r", subjectKey: "deploy-status", statement: "deploy is blocked", ttlMs: HOUR, now: T0 })
      expect(board.view(at(HOUR - 1)).some((entry) => entry.id === fact.id)).toBe(true)
      expect(board.view(at(HOUR + 1)).some((entry) => entry.id === fact.id)).toBe(false)
      expect(board.factActive(fact.id, fact.version, at(HOUR + 1))).toBe(false)
    } finally {
      await rm(dir, { recursive: true, force: true })
    }
  })

  test("TTL bounds growth: N facts, short TTL, advanced clock → view size ≤ cap", async () => {
    const { board, dir } = await openBlackboard()
    try {
      const count = 30
      for (let index = 0; index < count; index += 1) {
        await board.writeFact({ root: "/r", subjectKey: `s${index}`, statement: `f${index}`, ttlMs: HOUR, now: T0 })
      }
      const later = at(2 * HOUR)
      expect(board.view(later).length).toBe(0)
      // Cap enforcement: beyond GLOBAL_ENTRY_CAP active entries cannot accumulate.
      for (let index = 0; index < GLOBAL_ENTRY_CAP + 50; index += 1) {
        await board.writeFact({ root: "/r", subjectKey: `cap${index}`, statement: `f${index}`, now: T0 })
      }
      expect(board.view(T0).length).toBeLessThanOrEqual(GLOBAL_ENTRY_CAP)
    } finally {
      await rm(dir, { recursive: true, force: true })
    }
  })

  test("supersession: same root+subjectKey bumps version and invalidates the old fact", async () => {
    const { board, dir, records } = await openBlackboard(true)
    try {
      const first = await board.writeFact({ root: "/r", subjectKey: "deploy-status", statement: "deploy is blocked", citations: ["ses_1/msg_1"], now: T0 })
      const second = await board.writeFact({ root: "/r", subjectKey: "deploy-status", statement: "deploy was approved", citations: ["ses_1/msg_2"], now: at(HOUR) })
      expect(second.fact.id).toBe(first.fact.id)
      expect(second.fact.version).toBe(2)
      const facts = board.view(at(HOUR)).filter((entry) => entry.kind === "fact")
      expect(facts.length).toBe(1)
      // A premise pinned to the superseded version is stale → re-decide.
      expect(board.factActive(second.fact.id, 1, at(HOUR))).toBe(false)
      expect(board.factActive(second.fact.id, 2, at(HOUR))).toBe(true)
      expect(records.some((record) => record.type === "BLACKBOARD_FACT_INVALIDATED")).toBe(true)
      expect(records.filter((record) => record.type === "BLACKBOARD_FACT_WRITTEN").length).toBe(2)
    } finally {
      await rm(dir, { recursive: true, force: true })
    }
  })

  test("rendering: decisions retained latest-3 per session and open questions visible", async () => {
    const { board, dir } = await openBlackboard()
    try {
      const actions: readonly (typeof ACTIONS)[number][] = ["ACCEPT", "STEER", "CONTINUE", "ESCALATE"]
      for (const [index, action] of actions.entries()) {
        await board.writeDecision({ root: "/r", tickID: `tick_${index}`, sessionID: "ses_1", action, rationale: `r${index}`, now: at(index * HOUR) })
      }
      const decisions = board.view(at(5 * HOUR)).filter((entry) => entry.kind === "decision")
      expect(decisions.length).toBe(3)
      const question = await board.openQuestion({ root: "/r", decisionKey: "dk1", queueItemID: "att_q1", question: "Hold the deploy?", now: at(4 * HOUR) })
      const active = board.view(at(4 * HOUR))
      expect(active.some((entry) => entry.id === question.id)).toBe(true)
      expect(board.view(at(4 * HOUR + 25 * HOUR)).some((entry) => entry.id === question.id)).toBe(false)
    } finally {
      await rm(dir, { recursive: true, force: true })
    }
  })

  test("concurrent merge: parallel writes serialize without losing entries", async () => {
    const { board, dir } = await openBlackboard()
    try {
      const writes = Array.from({ length: 25 }, (_, index) =>
        board.writeFact({ root: "/r", subjectKey: `k${index}`, statement: `f${index}`, now: T0 }))
      await Promise.all(writes)
      expect(board.view(T0).filter((entry) => entry.kind === "fact").length).toBe(25)
      const duels = Array.from({ length: 10 }, () =>
        board.writeFact({ root: "/r", subjectKey: "hot-key", statement: `v-${Math.random()}`, now: T0 }))
      await Promise.all(duels)
      expect(board.view(T0).filter((entry) => entry.kind === "fact" && entry.subjectKey === "hot-key").length).toBe(1)
    } finally {
      await rm(dir, { recursive: true, force: true })
    }
  })

  test("later fact retires earlier open question: revalidate → retired-by-evidence citing it", async () => {
    const { board, dir } = await openBlackboard()
    try {
      const item = queueItem()
      const question = await board.openQuestion({ root: "/root", decisionKey: item.decisionKey, queueItemID: item.id, question: item.question, now: T0 })
      expect(question.decisionKey).toBe(item.decisionKey)
      const { fact, answeredQuestions } = await board.writeFact({
        root: "/root",
        subjectKey: item.decisionKey,
        statement: "operator approved the deploy",
        citations: ["ses_console/msg_9"],
        now: at(HOUR),
      })
      expect(answeredQuestions.map((entry) => entry.id)).toContain(question.id)
      const answer = board.answerFor(item.decisionKey, at(HOUR))
      expect(answer?.entryID).toBe(fact.id)
      const outcome = revalidate(item, allTrueSources({ answeredElsewhere: () => (answer === undefined ? undefined : { source: "blackboard", entryID: answer.entryID, version: answer.version }) }), { now: at(HOUR), graceMs: 60_000, ttlMs: 24 * HOUR })
      expect(outcome.kind).toBe("retired-by-evidence")
      if (outcome.kind === "retired-by-evidence") {
        expect(outcome.evidence[0]?.source).toBe("blackboard")
        expect(outcome.evidence[0]).toMatchObject({ entryID: fact.id, version: fact.version })
      }
    } finally {
      await rm(dir, { recursive: true, force: true })
    }
  })

  test("expired fact answer does not retire a live ticket", async () => {
    const { board, dir } = await openBlackboard()
    try {
      const item = queueItem()
      await board.openQuestion({ root: "/root", decisionKey: item.decisionKey, queueItemID: item.id, question: item.question, now: T0 })
      await board.writeFact({ root: "/root", subjectKey: item.decisionKey, statement: "temporary answer", ttlMs: HOUR, now: T0 })

      const answer = board.answerFor(item.decisionKey, at(2 * HOUR))
      const outcome = revalidate(item, allTrueSources({ answeredElsewhere: () => (answer === undefined ? undefined : { source: "blackboard", entryID: answer.entryID, version: answer.version }) }), { now: at(2 * HOUR), graceMs: 60_000, ttlMs: 24 * HOUR })

      expect(answer).toBeUndefined()
      expect(outcome.kind).toBe("valid")
    } finally {
      await rm(dir, { recursive: true, force: true })
    }
  })

  test("parseTickDecided narrows TICK_DECIDED payloads and rejects others", () => {
    const record = { seq: 1, timestamp: T0, type: "TICK_DECIDED", payload: { decision: { action: "CONTINUE", rationale: "worker asked go-ahead", citations: [], confidence: 0.8 }, root: "/projects/beacon", sessionID: "ses_1", messageID: "msg_1" }, prevHash: "GENESIS", hash: "0".repeat(64) } as const satisfies LedgerRecord
    const parsed = parseTickDecided(record)
    expect(parsed?.action).toBe("CONTINUE")
    expect(parsed?.sessionID).toBe("ses_1")
    expect(parsed?.root).toBe("/projects/beacon")
    const other = { ...record, type: "TICK_SKIPPED" } as const satisfies LedgerRecord
    expect(parseTickDecided(other)).toBeUndefined()
    const malformed = { ...record, payload: { decision: { action: "EXPLODE", rationale: "x" }, sessionID: "ses_1" } } as const satisfies LedgerRecord
    expect(parseTickDecided(malformed)).toBeUndefined()
  })

  test("assembler renders the L3 self-memory block within its token cap", async () => {
    const { assembleContext } = await import("../src/assembler")
    const target = { sessionID: "ses_1", userMessageID: "msg_u1", assistantMessageID: "msg_a1", origin: "human" as const, userText: "u", assistantText: "a", transcript: "U: u\nA: a" }
    const rendered = assembleContext({
      target,
      targetHistory: [],
      siblingChanges: {},
      targetHistoryCapPairs: 50,
      siblingTurnWindow: 3,
      tokenBudget: 20_000,
      selfMemory: {
        decisions: [
          { action: "CONTINUE", rationale: "worker asked go-ahead for step 3", decidedAtMs: Date.parse(T0) - 12 * 60_000 },
          { action: "ACCEPT", rationale: "reply complete", decidedAtMs: Date.parse(T0) - 5 * 60 * 60_000 },
        ],
        openItems: [{ id: "att_1", question: "Drop the Redis migration?", createdAtMs: Date.parse(T0) - 3 * 60 * 60_000 }],
        nowMs: Date.parse(T0),
      },
    })
    const block = rendered.text.slice(rendered.text.indexOf("L3 SELF-MEMORY"))
    expect(block).toContain("YOUR RECENT DECISIONS on this session:")
    expect(block).toContain("CONTINUE (12m ago) — worker asked go-ahead for step 3")
    expect(block).toContain("OPEN ATTENTION ITEMS on this project's root:")
    expect(block).toContain("att_1 (3h ago): Drop the Redis migration?")
    expect(block.length).toBeLessThanOrEqual(500 * 4)
    const without = assembleContext({ target, targetHistory: [], siblingChanges: {}, targetHistoryCapPairs: 50, siblingTurnWindow: 3, tokenBudget: 20_000 })
    expect(without.text).not.toContain("L3 SELF-MEMORY")
  })
})
