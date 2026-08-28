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

export const LEDGER_TYPES = [
  "WORKER_TURN_COMPLETED",
  "TICK_DECIDED",
  "CLASSIFIED_UNKNOWN",
  "METRICS_SNAPSHOT",
  "ERROR",
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
