import { describe, expect, test } from "bun:test"
import { mkdtemp, rm } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"
import {
  AttentionQueue,
  decisionKey,
  itemState,
  normalizeSubject,
  revalidate,
  selectNext,
  type ProposeInput,
  type ProposeResult,
  type RevalidationConfig,
  type RevalidationSources,
} from "../src/queue"
import type { AttentionQueueItem, EvidenceRef, OriginTick, Premise, SurfaceRecord, TickID } from "../src/types"

const NOW = "2026-09-19T12:00:00.000Z"
const CONFIG: RevalidationConfig = { now: NOW, graceMs: 60_000, ttlMs: 24 * 60 * 60 * 1000 }

function tick(id: TickID): OriginTick {
  return {
    tickID: id,
    ledgerSeq: 1,
    decision: { action: "ESCALATE", rationale: "r", citations: [], confidence: 0.9 },
    citations: [],
    informationNeeds: [],
    contextDigest: "digest",
  }
}

function premise(id: string): Premise {
  return { id, kind: "no-newer-turn", sessionID: "ses-a", latestMessageID: "msg-a1", observedAt: NOW }
}

function makeItem(overrides: Partial<AttentionQueueItem> = {}): AttentionQueueItem {
  const base: AttentionQueueItem = {
    schemaVersion: 1,
    id: "att_test0001",
    version: 1,
    decisionKey: "key-1",
    kind: "decision",
    origin: tick("tick_1"),
    target: { root: "/root", sessionID: "ses-a", userMessageID: "msg-u1", assistantMessageID: "msg-a1" },
    actionClass: "ESCALATE",
    escalationKind: "DECISION",
    question: "Deploy to prod?",
    rationale: "needs operator",
    priority: { stakes: 4, urgency: 4, confidence: 0.8, freshness: 1, createdAt: NOW },
    premises: [premise("p1")],
    relatedItemIDs: [],
    lifecycle: [{ state: "revalidated", at: NOW, result: "valid", evidence: [] }],
    poisonCount: 0,
  }
  return { ...base, ...overrides }
}

function makeSources(overrides: Partial<RevalidationSources> = {}): RevalidationSources {
  return {
    targetExists: () => true,
    targetIdle: () => true,
    latestMessageID: () => "msg-a1",
    targetTurnAborted: () => false,
    ticketOpen: () => true,
    blackboardFactActive: () => true,
    canonicalItemFor: () => undefined,
    answeredElsewhere: () => undefined,
    approvalRequired: () => false,
    modePermits: () => true,
    citationsAdmissible: () => true,
    ...overrides,
  }
}

function proposal(overrides: Partial<ProposeInput> = {}): ProposeInput {
  return {
    kind: "decision",
    origin: tick("tick_1"),
    target: { root: "/root", sessionID: "ses-a", userMessageID: "msg-u1", assistantMessageID: "msg-a1" },
    actionClass: "ESCALATE",
    escalationKind: "DECISION",
    question: "Deploy to prod?",
    rationale: "needs operator",
    priority: { stakes: 4, urgency: 4, confidence: 0.8, freshness: 1, createdAt: NOW },
    premises: [premise("p1")],
    ...overrides,
  }
}

/** All proposals in this suite are ESCALATE-class; a protected-CONTINUE block is unexpected here. */
async function proposeItem(queue: AttentionQueue, input: ProposeInput): Promise<Exclude<ProposeResult, { kind: "blocked" }>> {
  const result = await queue.propose(input)
  if (result.kind === "blocked") throw new Error(`unexpected blocked proposal: ${result.reason}`)
  return result
}


async function openQueue(): Promise<{ queue: AttentionQueue; dir: string; events: string[] }> {
  const dir = await mkdtemp(join(tmpdir(), "supervisor-queue-"))
  const events: string[] = []
  const queue = await AttentionQueue.open({ path: join(dir, "queue.json"), append: async (type) => { events.push(type) } })
  return { queue, dir, events }
}

test("repeated re-decide stays open without poison and emits high-water diagnostics", async () => {
  // Given
  const { queue, dir, events } = await openQueue()
  try {
    const created = await proposeItem(queue, proposal())
    const changed = makeSources({ latestMessageID: () => "msg-new" })
    // When
    for (let count = 1; count <= 8; count += 1) {
      const result = await queue.revalidate(created.item.id, changed, CONFIG)
      // Then
      expect(result.redecide).toBe(true)
      expect(result.item.poisonCount).toBe(0)
      expect(itemState(result.item)).toBe("revalidated")
      expect(result.item.redecideCount).toBe(count)
    }
    expect(queue.digest).toHaveLength(2)
    expect(events.filter((type) => type === "QUEUE_REDECIDE_DIAGNOSTIC")).toHaveLength(2)
  } finally { await rm(dir, { recursive: true, force: true }) }
})

test("newer-turn evidence retires instead of requesting re-decision", async () => {
  // Given
  const { queue, dir } = await openQueue()
  try {
    const created = await proposeItem(queue, proposal())
    // When
    const result = await queue.revalidate(created.item.id, makeSources({ latestMessageID: () => "msg-new", answeredElsewhere: () => ({ source: "session", sessionID: "ses-a", messageID: "msg-new", digest: "answered" }) }), CONFIG)
    // Then
    expect(itemState(result.item)).toBe("resolved")
    expect(result.outcome.kind).toBe("retired-by-evidence")
  } finally { await rm(dir, { recursive: true, force: true }) }
})

describe("decisionKey", () => {
  test("normalizeSubject strips ticket numbers, timestamps, and whitespace", () => {
    expect(normalizeSubject("Q17: Deploy  2026-09-19T12:00:00Z now?")).toBe("deploy now?")
  })
  test("is stable across ticks and ignores the ticket prefix", () => {
    const first = decisionKey({ root: "/r", sessionID: "s", actionClass: "ESCALATE", escalationKind: "DECISION", subject: "Q1: deploy?" })
    const second = decisionKey({ root: "/r", sessionID: "s", actionClass: "ESCALATE", escalationKind: "DECISION", subject: "deploy?" })
    expect(first).toBe(second)
  })
})

describe("revalidate §4 matrix", () => {
  test("valid when every premise holds", () => {
    expect(revalidate(makeItem(), makeSources(), CONFIG).kind).toBe("valid")
  })
  test("superseded when the target session is gone", () => {
    expect(revalidate(makeItem(), makeSources({ targetExists: () => false }), CONFIG).kind).toBe("superseded")
  })
  test("temporarily-invalid when the target is busy (re-prioritize)", () => {
    const outcome = revalidate(makeItem(), makeSources({ targetIdle: () => false }), CONFIG)
    expect(outcome.kind).toBe("temporarily-invalid")
    if (outcome.kind === "temporarily-invalid") expect(Date.parse(outcome.notBefore)).toBeGreaterThan(Date.parse(NOW))
  })
  test("re-decide when a newer turn changed the context", () => {
    expect(revalidate(makeItem(), makeSources({ latestMessageID: () => "msg-a2" }), CONFIG).kind).toBe("re-decide")
  })
  test("retired-by-evidence when a newer turn answers the need", () => {
    const evidence: EvidenceRef = { source: "session", sessionID: "ses-a", messageID: "msg-a2", digest: "d" }
    const outcome = revalidate(makeItem(), makeSources({ latestMessageID: () => "msg-a2", answeredElsewhere: () => evidence }), CONFIG)
    expect(outcome.kind).toBe("retired-by-evidence")
  })
  test("D295-abort shape: an aborted target turn is materially changed", () => {
    expect(revalidate(makeItem(), makeSources({ targetTurnAborted: () => true }), CONFIG).kind).toBe("materially-changed")
  })
  test("retired-by-evidence when answered elsewhere", () => {
    const evidence: EvidenceRef = { source: "blackboard", entryID: "fact-1", version: 2 }
    expect(revalidate(makeItem(), makeSources({ answeredElsewhere: () => evidence }), CONFIG).kind).toBe("retired-by-evidence")
  })
  test("downgrade-console-only when citations are inadmissible", () => {
    expect(revalidate(makeItem(), makeSources({ citationsAdmissible: () => false }), CONFIG).kind).toBe("downgrade-console-only")
  })
  test("expired past the class TTL", () => {
    const old = makeItem({ priority: { stakes: 4, urgency: 4, confidence: 0.8, freshness: 1, createdAt: "2026-09-17T12:00:00.000Z" } })
    expect(revalidate(old, makeSources(), CONFIG).kind).toBe("expired")
  })
  test("APPROVAL never auto-expires", () => {
    const approval = makeItem({ escalationKind: "APPROVAL", priority: { stakes: 5, urgency: 5, confidence: 0.9, freshness: 1, createdAt: "2026-09-01T12:00:00.000Z" } })
    expect(revalidate(approval, makeSources(), CONFIG).kind).toBe("valid")
  })
})

describe("AttentionQueue dedupe", () => {
  test("merges concurrent identical escalations into one item", async () => {
    const { queue, dir, events } = await openQueue()
    const first = await proposeItem(queue, proposal({ origin: tick("tick_1"), premises: [premise("p1")] }))
    const second = await proposeItem(queue, proposal({ origin: tick("tick_2"), premises: [premise("p2")], priority: { stakes: 4, urgency: 4, confidence: 0.8, freshness: 1, createdAt: "2026-09-19T13:00:00.000Z" } }))
    expect(first.kind).toBe("created")
    expect(second.kind).toBe("merged")
    expect(queue.items).toHaveLength(1)
    const item = queue.items[0]
    if (item === undefined) throw new Error("expected one item")
    expect(item.version).toBe(2)
    expect(item.premises.map((entry) => entry.id).sort()).toEqual(["p1", "p2"])
    expect(item.priority.createdAt).toBe(NOW)
    expect(events).toEqual(["QUEUE_ITEM_PROPOSED", "QUEUE_ITEM_MERGED"])
    await rm(dir, { recursive: true, force: true })
  })
})

describe("AttentionQueue lease", () => {
  test("lease records precede confirmed delivery and confirmation is idempotent", async () => {
    // Given
    const { queue, dir, events } = await openQueue()
    try {
      const created = await proposeItem(queue, proposal())
      // When
      const acquired = await queue.acquireLease(created.item.id, { channelID: "console", now: NOW })
      if (acquired.kind !== "acquired") throw new Error("expected lease")
      // Then
      expect(events).toContain("QUEUE_ITEM_LEASED")
      expect(events).not.toContain("QUEUE_ITEM_SURFACED")
      await queue.confirmSurfaced(created.item.id, acquired.lease.presentationID, NOW)
      await queue.confirmSurfaced(created.item.id, acquired.lease.presentationID, NOW)
      expect(events.filter((type) => type === "QUEUE_ITEM_SURFACED")).toHaveLength(1)
      expect(events.indexOf("QUEUE_ITEM_LEASED")).toBeLessThan(events.indexOf("QUEUE_ITEM_SURFACED"))
    } finally { await rm(dir, { recursive: true, force: true }) }
  })
  test("enforces a single global presentation lease", async () => {
    const { queue, dir } = await openQueue()
    const first = await proposeItem(queue, proposal({ question: "A?" }))
    const second = await proposeItem(queue, proposal({ question: "B?", target: { root: "/root", sessionID: "ses-b", userMessageID: "msg-u2" } }))
    const acquired = await queue.acquireLease(first.item.id, { channelID: "console", now: NOW })
    if (acquired.kind !== "acquired") throw new Error("expected first lease")
    const denied = await queue.acquireLease(second.item.id, { channelID: "console", now: NOW })
    expect(denied.kind).toBe("denied")
    if (denied.kind === "denied") expect(denied.heldBy).toBe(first.item.id)
    await queue.defer(acquired.lease.presentationID, "2026-09-19T12:05:00.000Z", NOW)
    const reacquired = await queue.acquireLease(second.item.id, { channelID: "console", now: NOW })
    expect(reacquired.kind).toBe("acquired")
    await rm(dir, { recursive: true, force: true })
  })
})

describe("AttentionQueue poison handling", () => {
  test("three failures mark poison-suspect, the fourth expires the item", async () => {
    const { queue, dir } = await openQueue()
    const created = await proposeItem(queue, proposal())
    const failing = makeSources({ citationsAdmissible: () => false })
    expect((await queue.revalidate(created.item.id, failing, CONFIG)).poison).toBe("none")
    expect((await queue.revalidate(created.item.id, failing, CONFIG)).poison).toBe("none")
    const third = await queue.revalidate(created.item.id, failing, CONFIG)
    expect(third.poison).toBe("suspect")
    expect(third.outcome.kind).toBe("re-decide")
    const fourth = await queue.revalidate(created.item.id, failing, CONFIG)
    expect(fourth.poison).toBe("expired")
    expect(itemState(fourth.item)).toBe("resolved")
    expect(queue.digest.some((entry) => entry.includes(created.item.id))).toBe(true)
    await rm(dir, { recursive: true, force: true })
  })
})

describe("AttentionQueue persistence", () => {
  test("persists atomically and releases a stale lease on recovery", async () => {
    const dir = await mkdtemp(join(tmpdir(), "supervisor-queue-"))
    const path = join(dir, "queue.json")
    const queue = await AttentionQueue.open({ path, append: async () => {} })
    const created = await proposeItem(queue, proposal())
    const acquired = await queue.acquireLease(created.item.id, { channelID: "console", now: NOW, ttlMs: 1000 })
    if (acquired.kind !== "acquired") throw new Error("expected lease")
    const reloaded = await AttentionQueue.open({ path, append: async () => {}, now: "2026-09-19T12:00:02.000Z" })
    expect(reloaded.lease).toBeUndefined()
    expect(reloaded.items).toHaveLength(1)
    expect(reloaded.selectNext("2026-09-19T12:00:02.000Z")?.id).toBe(created.item.id)
    await rm(dir, { recursive: true, force: true })
  })
})

describe("selectNext prioritization", () => {
  test("APPROVAL preempts a higher-scoring non-approval item", () => {
    const approval = makeItem({ id: "att_appr", escalationKind: "APPROVAL", priority: { stakes: 1, urgency: 1, confidence: 0.5, freshness: 1, createdAt: NOW } })
    const urgent = makeItem({ id: "att_urgent", escalationKind: "DECISION", priority: { stakes: 5, urgency: 5, confidence: 0.9, freshness: 1, createdAt: NOW } })
    expect(selectNext({ items: [urgent, approval], lease: undefined, surfaceLog: [], now: NOW })?.id).toBe("att_appr")
  })
  test("root fairness: a root with two consecutive surfaces yields to another root", () => {
    const rootA = makeItem({ id: "att_a", target: { root: "/a", sessionID: "s", userMessageID: "u" }, priority: { stakes: 5, urgency: 5, confidence: 0.9, freshness: 1, createdAt: NOW } })
    const rootB = makeItem({ id: "att_b", target: { root: "/b", sessionID: "s", userMessageID: "u" }, priority: { stakes: 5, urgency: 5, confidence: 0.9, freshness: 1, createdAt: NOW } })
    const surfaceLog: SurfaceRecord[] = [
      { root: "/a", itemID: "att_a", at: NOW },
      { root: "/a", itemID: "att_a", at: NOW },
    ]
    expect(selectNext({ items: [rootA, rootB], lease: undefined, surfaceLog, now: NOW })?.id).toBe("att_b")
  })
})

describe("openItemsByRoot", () => {
  test("counts non-resolved items per root; resolved items excluded", async () => {
    const { openItemsByRoot } = await import("../src/queue")
    const open = (root: string, id: `att_${string}`) => makeItem({ id, target: { root, sessionID: "ses-a", userMessageID: "u1" }, lifecycle: [{ state: "proposed", at: NOW, actor: "tick" }] })
    const resolved = (root: string, id: `att_${string}`) => makeItem({ id, target: { root, sessionID: "ses-a", userMessageID: "u1" }, lifecycle: [{ state: "resolved", at: NOW, disposition: "propagated", evidence: [] }] })
    const items = [open("/root-a", "att_1"), open("/root-b", "att_2"), open("/root-a", "att_3"), resolved("/root-a", "att_4")]
    expect(openItemsByRoot(items)).toEqual({ "/root-a": 2, "/root-b": 1 })
    expect(openItemsByRoot([])).toEqual({})
  })
})

describe("AttentionQueue idempotency guards", () => {
  test("resolving an already-resolved item is a no-op (no duplicate ledger row)", async () => {
    const { queue, dir, events } = await openQueue()
    const created = await proposeItem(queue, proposal())
    const first = await queue.resolve(created.item.id, { disposition: "propagated", evidence: [], now: NOW, reason: "delivered" })
    const second = await queue.resolve(created.item.id, { disposition: "propagated", evidence: [], now: NOW, reason: "delivered again" })
    expect(second).toBe(first)
    expect(second.lifecycle).toHaveLength(first.lifecycle.length)
    expect(events.filter((type) => type === "QUEUE_ITEM_RESOLVED")).toHaveLength(1)
    await rm(dir, { recursive: true, force: true })
  })

  test("markAnswered on an already-answered item is a no-op (no lifecycle row)", async () => {
    const { queue, dir, events } = await openQueue()
    const created = await proposeItem(queue, proposal())
    const first = await queue.markAnswered(created.item.id, "reply_1", "console", NOW)
    const second = await queue.markAnswered(created.item.id, "reply_2", "console", NOW)
    expect(second).toBe(first)
    expect(second.lifecycle).toHaveLength(first.lifecycle.length)
    expect(events.filter((type) => type === "QUEUE_REPLY_RECEIVED")).toHaveLength(1)
    await rm(dir, { recursive: true, force: true })
  })
})
