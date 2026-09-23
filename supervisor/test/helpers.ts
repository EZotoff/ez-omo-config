// Shared operator-view test fixtures (reusable by Task 3's reader/validator tests).
import type { AttentionQueueItem, OriginTick, Premise } from "../src/types"

export const T0 = Date.parse("2026-09-23T12:00:00.000Z")

export function fixtureTick(ledgerSeq: number): OriginTick {
  return {
    tickID: `tick_${ledgerSeq}`,
    ledgerSeq,
    decision: { action: "ESCALATE", rationale: "r", citations: [], confidence: 0.9 },
    citations: [],
    informationNeeds: [],
    contextDigest: "digest",
  }
}

export function fixturePremise(id: string): Premise {
  return { id, kind: "no-newer-turn", sessionID: "ses-a", latestMessageID: "msg-a1", observedAt: "2026-09-23T11:59:00.000Z" }
}

export type FixtureOverrides = Partial<AttentionQueueItem> & {
  readonly sessionTitle?: string
}

/** One live ESCALATE card; override id/origin.ledgerSeq/target fields per scenario. */
export function fixtureItem(overrides: FixtureOverrides = {}): AttentionQueueItem {
  const index = overrides.id ?? "att_fix0001"
  const base: AttentionQueueItem = {
    schemaVersion: 1,
    id: index,
    version: 1,
    decisionKey: `key-${index}`,
    kind: "decision",
    origin: fixtureTick(5),
    target: { root: "/home/user/proj", sessionID: "ses-a", userMessageID: "msg-u1", assistantMessageID: "msg-a1" },
    actionClass: "ESCALATE",
    escalationKind: "DECISION",
    question: "Deploy to prod?",
    rationale: "needs operator",
    priority: { stakes: 4, urgency: 4, confidence: 0.8, freshness: 1, createdAt: "2026-09-23T11:00:00.000Z" },
    premises: [fixturePremise("p1")],
    relatedItemIDs: [],
    lifecycle: [{ state: "revalidated", at: "2026-09-23T11:59:30.000Z", result: "valid", evidence: [] }],
    poisonCount: 0,
  }
  const { sessionTitle, ...rest } = overrides
  const merged: AttentionQueueItem = { ...base, ...rest }
  return sessionTitle === undefined
    ? merged
    : { ...merged, target: { ...merged.target, sessionTitle } }
}
