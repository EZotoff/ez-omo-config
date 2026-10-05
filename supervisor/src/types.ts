export const ORIGINS = [
  "human",
  "machine-synthetic",
  "machine-template",
  "supervisor",
  "unknown",
] as const
export type Origin = (typeof ORIGINS)[number]

export type Part = {
  readonly id: string
  readonly messageID: string
  readonly type: string
  readonly text?: string
  readonly synthetic?: boolean
  readonly tool?: string
  readonly state?: unknown
}

export type Message = {
  readonly id: string
  readonly sessionID: string
  readonly role: "user" | "assistant"
  readonly time: { readonly created: number; readonly completed?: number }
  readonly agent?: string
  readonly error?: unknown
  readonly finish?: string
  readonly parts: readonly Part[]
}

export type Session = {
  readonly id: string
  readonly directory: string
  readonly parentID?: string
  readonly title?: string
  readonly timeUpdatedMs?: number
}

export type Turn = {
  readonly sessionID: string
  readonly userMessageID: string
  readonly assistantMessageID?: string
  readonly origin: Origin
  readonly userText: string
  readonly assistantText: string
  readonly transcript: string
  /** True when the assistant run trails a RUNNING question-tool part — the session is blocked on the operator's dialog answer (2026-10-05 incident class). */
  readonly awaitingOperatorAnswer?: boolean
}

export const ACTIONS = ["ACCEPT", "ABSTAIN", "CONTINUE", "STEER", "REFORMULATE", "ESCALATE"] as const
export type Action = (typeof ACTIONS)[number]

export type Citation = {
  readonly session: string
  readonly messageID: string
  readonly quote: string
}

export type Decision = {
  readonly action: Action
  readonly target?: string
  readonly rationale: string
  readonly citations: readonly Citation[]
  readonly confidence: number
}

export type QueueItemID = `att_${string}`
export type TickID = `tick_${string}`
export type DecisionKey = string
export type ISO8601 = string

export type EscalationKind = "DECISION" | "INFORMATION" | "APPROVAL"
export type QueueKind = "decision" | "information-need"

export type QueuePriorityInputs = {
  readonly stakes: 1 | 2 | 3 | 4 | 5
  readonly urgency: 1 | 2 | 3 | 4 | 5
  readonly confidence: number
  readonly freshness: number
  readonly createdAt: ISO8601
  readonly notBefore?: ISO8601
}

export type InformationNeed = {
  readonly question: string
  readonly scope: "session_history" | "ledger" | "session_cards"
  readonly target: string
  readonly why: string
  readonly expectedEffect: string
}

export type OriginTick = {
  readonly tickID: TickID
  readonly ledgerSeq: number
  readonly decision: Decision
  readonly citations: readonly Citation[]
  readonly informationNeeds: readonly InformationNeed[]
  readonly contextDigest: string
}

export type TargetRef = {
  readonly root: string
  readonly sessionID: string
  readonly userMessageID: string
  readonly assistantMessageID?: string
  readonly sessionTitle?: string
}

export type Premise =
  | { readonly id: string; readonly kind: "session-idle"; readonly sessionID: string; readonly observedAt: ISO8601 }
  | { readonly id: string; readonly kind: "no-newer-turn"; readonly sessionID: string; readonly latestMessageID: string; readonly observedAt: ISO8601 }
  | { readonly id: string; readonly kind: "ticket-open"; readonly ticketID: QueueItemID; readonly observedVersion: number }
  | { readonly id: string; readonly kind: "blackboard-fact"; readonly factID: string; readonly factVersion: number; readonly sourceCitationIDs: readonly string[] }
  | { readonly id: string; readonly kind: "sibling-decision"; readonly tickID: TickID; readonly ledgerSeq: number }
  | { readonly id: string; readonly kind: "operator-approval-required"; readonly rationale: string }

export type EvidenceRef =
  | { readonly source: "ledger"; readonly seq: number }
  | { readonly source: "session"; readonly sessionID: string; readonly messageID: string; readonly digest: string }
  | { readonly source: "queue"; readonly itemID: QueueItemID; readonly version: number }
  | { readonly source: "blackboard"; readonly entryID: string; readonly version: number }

export type ResolutionDisposition = "propagated" | "retired-by-evidence" | "superseded" | "expired"

export type LifecycleEvent =
  | { readonly state: "proposed"; readonly at: ISO8601; readonly actor: string }
  | { readonly state: "revalidated"; readonly at: ISO8601; readonly result: "valid" | "temporarily-invalid" | "materially-changed"; readonly evidence: readonly EvidenceRef[] }
  | { readonly state: "surfaced"; readonly at: ISO8601; readonly channelID: string; readonly presentationID: string; readonly contextTag?: string }
  | { readonly state: "answered"; readonly at: ISO8601; readonly replyEventID: string; readonly channelID: string }
  | { readonly state: "resolved"; readonly at: ISO8601; readonly disposition: ResolutionDisposition; readonly evidence: readonly EvidenceRef[]; readonly replacementItemID?: QueueItemID }

export type AttentionQueueItem = {
  readonly schemaVersion: 1
  readonly id: QueueItemID
  readonly version: number
  readonly decisionKey: DecisionKey
  readonly kind: QueueKind
  readonly origin: OriginTick
  readonly target: TargetRef
  readonly actionClass: Action
  readonly escalationKind?: EscalationKind
  readonly question: string
  readonly rationale: string
  readonly priority: QueuePriorityInputs
  readonly premises: readonly Premise[]
  readonly relatedItemIDs: readonly QueueItemID[]
  readonly lifecycle: readonly LifecycleEvent[]
  readonly poisonCount: number
}

export type PresentationLease = {
  readonly presentationID: string
  readonly itemID: QueueItemID
  readonly channelID: string
  readonly acquiredAt: ISO8601
  readonly heartbeatAt: ISO8601
  readonly expiresAt: ISO8601
}

export type SurfaceRecord = {
  readonly root: string
  readonly itemID: QueueItemID
  readonly at: ISO8601
}

export type QueueSnapshot = {
  readonly schemaVersion: 1
  readonly items: readonly AttentionQueueItem[]
  readonly lease?: PresentationLease
  readonly surfaceLog: readonly SurfaceRecord[]
  readonly digest: readonly string[]
}

export const LEDGER_TYPES = [
  "WORKER_TURN_COMPLETED",
  "TICK_DECIDED",
  "TICK_SKIPPED",
  "ESCALATION_CREATED",
  "INTERVENTION_SENT",
  "CONSOLE_INITIALIZED",
  "CLASSIFIED_UNKNOWN",
  "METRICS_SNAPSHOT",
  "ERROR",
  "QUEUE_ITEM_PROPOSED",
  "QUEUE_ITEM_MERGED",
  "QUEUE_PROPOSAL_DEDUPED",
  "QUEUE_ITEM_REVALIDATED",
  "QUEUE_ITEM_SURFACED",
  "QUEUE_REPLY_RECEIVED",
  "QUEUE_REPLY_AMBIGUOUS",
  "QUEUE_PROPAGATION_PROPOSED",
  "QUEUE_PROPAGATED",
  "QUEUE_ITEM_RESOLVED",
  "QUEUE_SWEPT",
  "QUEUE_PROPAGATION_DELIVERED",
  "CHANNEL_DEFERRED",
  "BLACKBOARD_FACT_WRITTEN",
  "BLACKBOARD_FACT_INVALIDATED",
] as const
export type LedgerRecordType = (typeof LEDGER_TYPES)[number]

export type LedgerRecord = {
  readonly seq: number
  readonly timestamp: string
  readonly type: LedgerRecordType
  readonly payload: unknown
  readonly prevHash: string
  readonly hash: string
}

export type OriginRegistry = {
  readonly humanMessageIDs: ReadonlySet<string>
  readonly supervisorMessageIDs: ReadonlySet<string>
}

export function assertNever(value: never): never {
  throw new TypeError(`unexpected variant: ${JSON.stringify(value)}`)
}
