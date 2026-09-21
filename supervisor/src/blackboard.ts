import { randomUUID } from "node:crypto"
import { mkdir, readFile, rename, writeFile } from "node:fs/promises"
import { dirname } from "node:path"
import type { LedgerAppend } from "./queue"
import { ACTIONS, type Action, type DecisionKey, type ISO8601, type LedgerRecord, type QueueItemID, type TickID } from "./types"

/**
 * Cross-tick blackboard (queue spec §6): bounded working memory, NOT a second
 * source of truth — the hash-chained ledger remains canonical. The snapshot is
 * a materialized cache; single-writer discipline is enforced by serializing
 * every mutation through an in-process chain (like Ledger.append).
 */

export type BlackboardFact = {
  readonly kind: "fact"
  readonly id: string
  readonly version: number
  readonly root: string
  readonly subjectKey: string
  readonly statement: string
  readonly citations: readonly string[]
  readonly establishedAt: ISO8601
  readonly expiresAt: ISO8601
  readonly status: "active" | "invalidated"
}

export type BlackboardOpenQuestion = {
  readonly kind: "open-question"
  readonly id: string
  readonly root: string
  readonly decisionKey: DecisionKey
  readonly queueItemID: QueueItemID
  readonly question: string
  readonly openedAt: ISO8601
  readonly expiresAt: ISO8601
  readonly answeredBy?: string
}

export type BlackboardDecision = {
  readonly kind: "decision"
  readonly id: string
  readonly root: string
  readonly tickID: TickID
  readonly sessionID: string
  readonly action: Action
  readonly rationale: string
  readonly decidedAt: ISO8601
  readonly expiresAt: ISO8601
}

export type BlackboardEntry = BlackboardFact | BlackboardOpenQuestion | BlackboardDecision

export const FACT_TTL_MS = 7 * 24 * 60 * 60 * 1000
export const DECISION_TTL_MS = 7 * 24 * 60 * 60 * 1000
export const OPEN_QUESTION_TTL_MS = 24 * 60 * 60 * 1000
export const DECISIONS_PER_SESSION = 3
export const GLOBAL_ENTRY_CAP = 500
export const PER_ROOT_CAP = 100

type Snapshot = { readonly schemaVersion: 1; readonly entries: readonly BlackboardEntry[]; readonly answers: readonly { readonly decisionKey: DecisionKey; readonly entryID: string; readonly version: number }[] }

export type FactProposal = {
  readonly root: string
  readonly subjectKey: string
  readonly statement: string
  readonly citations?: readonly string[]
  readonly ttlMs?: number
  readonly now: ISO8601
}

export type WriteFactResult = {
  readonly fact: BlackboardFact
  /** Open questions (by decisionKey === subjectKey) this fact answered. */
  readonly answeredQuestions: readonly BlackboardOpenQuestion[]
}

const isExpired = (entry: BlackboardEntry, now: ISO8601): boolean => Date.parse(entry.expiresAt) <= Date.parse(now)

const entryRoot = (entry: BlackboardEntry): string => entry.root

export class Blackboard {
  private constructor(
    private readonly path: string,
    private readonly append: LedgerAppend | undefined,
    private snapshot: Snapshot,
    private chain: Promise<unknown> = Promise.resolve(),
  ) {}

  static async open(options: { readonly path: string; readonly append?: LedgerAppend }): Promise<Blackboard> {
    let snapshot: Snapshot = { schemaVersion: 1, entries: [], answers: [] }
    try {
      snapshot = JSON.parse(await readFile(options.path, "utf8")) as Snapshot
    } catch (error) {
      if (!(error instanceof Error) || !("code" in error) || error.code !== "ENOENT") throw error
    }
    return new Blackboard(options.path, options.append, snapshot)
  }

  /** Single-writer serialization: every mutation runs after the previous one. */
  private serialize<T>(operation: () => Promise<T>): Promise<T> {
    const next = this.chain.then(operation, operation)
    this.chain = next.catch(() => undefined)
    return next
  }

  private async persist(): Promise<void> {
    await mkdir(dirname(this.path), { recursive: true })
    const temporary = `${this.path}.tmp-${process.pid}-${randomUUID()}`
    await writeFile(temporary, JSON.stringify(this.snapshot, null, 2), { mode: 0o600 })
    await rename(temporary, this.path)
  }

  private active(entry: BlackboardEntry, now: ISO8601): boolean {
    if (isExpired(entry, now)) return false
    return entry.kind !== "fact" || entry.status === "active"
  }

  /** Supersession: a fact on the same root+subjectKey replaces the old one (id stable, version+1). */
  async writeFact(proposal: FactProposal): Promise<WriteFactResult> {
    return this.serialize(async () => {
      const previous = this.snapshot.entries.find(
        (entry): entry is BlackboardFact => entry.kind === "fact" && entry.root === proposal.root && entry.subjectKey === proposal.subjectKey && entry.status === "active",
      )
      const nowMs = Date.parse(proposal.now)
      const fact: BlackboardFact = {
        kind: "fact",
        id: previous?.id ?? `bb_${randomUUID()}`,
        version: (previous?.version ?? 0) + 1,
        root: proposal.root,
        subjectKey: proposal.subjectKey,
        statement: proposal.statement,
        citations: proposal.citations ?? [],
        establishedAt: proposal.now,
        expiresAt: new Date(nowMs + (proposal.ttlMs ?? FACT_TTL_MS)).toISOString(),
        status: "active",
      }
      const answered = this.snapshot.entries.filter(
        (entry): entry is BlackboardOpenQuestion => entry.kind === "open-question" && entry.decisionKey === proposal.subjectKey && this.active(entry, proposal.now),
      )
      const answers = [
        ...this.snapshot.answers.filter((answer) => !answered.some((question) => question.decisionKey === answer.decisionKey)),
        ...answered.map((question) => ({ decisionKey: question.decisionKey, entryID: fact.id, version: fact.version })),
      ]
      this.snapshot = {
        schemaVersion: 1,
        entries: [
          ...this.snapshot.entries.filter((entry) => entry.kind !== "fact" || entry.id !== fact.id),
          fact,
        ],
        answers,
      }
      if (previous !== undefined) await this.append?.("BLACKBOARD_FACT_INVALIDATED", { entryID: previous.id, version: previous.version, root: previous.root, subjectKey: previous.subjectKey, reason: "superseded" })
      await this.append?.("BLACKBOARD_FACT_WRITTEN", { entryID: fact.id, version: fact.version, root: fact.root, subjectKey: fact.subjectKey })
      await this.pruneInternal(proposal.now, new Set(answered.map((question) => question.queueItemID)))
      return { fact, answeredQuestions: answered }
    })
  }

  /** Retention: latest 3 decisions per session (7-day TTL pruned lazily). */
  async writeDecision(input: { readonly root: string; readonly tickID: TickID; readonly sessionID: string; readonly action: Action; readonly rationale: string; readonly now: ISO8601 }): Promise<void> {
    return this.serialize(async () => {
      const decision: BlackboardDecision = {
        kind: "decision",
        id: `bb_${randomUUID()}`,
        root: input.root,
        tickID: input.tickID,
        sessionID: input.sessionID,
        action: input.action,
        rationale: input.rationale,
        decidedAt: input.now,
        expiresAt: new Date(Date.parse(input.now) + DECISION_TTL_MS).toISOString(),
      }
      const kept = this.snapshot.entries.filter((entry) => entry.kind !== "decision" || entry.sessionID !== input.sessionID)
      const sessionDecisions = [...this.snapshot.entries.filter((entry): entry is BlackboardDecision => entry.kind === "decision" && entry.sessionID === input.sessionID), decision]
        .sort((left, right) => Date.parse(left.decidedAt) - Date.parse(right.decidedAt))
        .slice(-DECISIONS_PER_SESSION)
      this.snapshot = { schemaVersion: 1, entries: [...kept, ...sessionDecisions], answers: this.snapshot.answers }
      await this.pruneInternal(input.now, new Set())
    })
  }

  async openQuestion(input: { readonly root: string; readonly decisionKey: DecisionKey; readonly queueItemID: QueueItemID; readonly question: string; readonly now: ISO8601 }): Promise<BlackboardOpenQuestion> {
    return this.serialize(async () => {
      const question: BlackboardOpenQuestion = {
        kind: "open-question",
        id: `bb_${randomUUID()}`,
        root: input.root,
        decisionKey: input.decisionKey,
        queueItemID: input.queueItemID,
        question: input.question,
        openedAt: input.now,
        expiresAt: new Date(Date.parse(input.now) + OPEN_QUESTION_TTL_MS).toISOString(),
      }
      this.snapshot = { schemaVersion: 1, entries: [...this.snapshot.entries.filter((entry) => entry.kind !== "open-question" || entry.queueItemID !== input.queueItemID), question], answers: this.snapshot.answers }
      await this.pruneInternal(input.now, new Set([input.queueItemID]))
      return question
    })
  }

  /** Materialized active view (facts/decisions/questions, expiry- and cap-bounded). */
  view(now: ISO8601): readonly BlackboardEntry[] {
    return this.snapshot.entries.filter((entry) => this.active(entry, now))
  }

  /** Premise revalidation: a pinned fact is active only if still current (same version, not invalidated/expired). */
  factActive(factID: string, factVersion: number, now: ISO8601): boolean {
    const entry = this.snapshot.entries.find((candidate) => candidate.kind === "fact" && candidate.id === factID)
    return entry !== undefined && entry.kind === "fact" && entry.status === "active" && entry.version === factVersion && !isExpired(entry, now)
  }

  /** Retire-by-evidence hook: the fact that answered an open question, for the queue's answeredElsewhere source. */
  answerFor(decisionKey: DecisionKey, now: ISO8601): { readonly entryID: string; readonly version: number } | undefined {
    return this.snapshot.answers.find((answer) => answer.decisionKey === decisionKey && this.factActive(answer.entryID, answer.version, now))
  }

  /**
   * Hard caps: evict expired first, then oldest uncited facts. Entries referenced
   * by unresolved queue items (via queueItemID or fact id) are never evicted.
   */
  private async pruneInternal(now: ISO8601, protectedIDs: ReadonlySet<string>): Promise<void> {
    const protectedEntry = (entry: BlackboardEntry): boolean =>
      protectedIDs.has(entry.id) || (entry.kind === "open-question" && protectedIDs.has(entry.queueItemID))
    let entries = this.snapshot.entries.filter((entry) => protectedEntry(entry) || !isExpired(entry, now))
    if (entries.length > GLOBAL_ENTRY_CAP) {
      const evictable = entries.filter((entry): entry is BlackboardFact => !protectedEntry(entry) && entry.kind === "fact" && entry.citations.length === 0)
      const excess = entries.length - GLOBAL_ENTRY_CAP
      const byRoot = new Map<string, number>()
      for (const entry of entries) byRoot.set(entryRoot(entry), (byRoot.get(entryRoot(entry)) ?? 0) + 1)
      const oldestFirst = [...evictable].sort((left, right) => Date.parse(left.establishedAt) - Date.parse(right.establishedAt))
      const evict = new Set(oldestFirst.slice(0, excess).map((entry) => entry.id))
      entries = entries.filter((entry) => !evict.has(entry.id) || protectedEntry(entry))
    }
    for (const [root, count] of byRootCounts(entries)) {
      if (count <= PER_ROOT_CAP) continue
      const evictable = entries.filter((entry): entry is BlackboardFact => entry.root === root && !protectedEntry(entry) && entry.kind === "fact" && entry.citations.length === 0)
      const excess = count - PER_ROOT_CAP
      const oldestFirst = [...evictable].sort((left, right) => Date.parse(left.establishedAt) - Date.parse(right.establishedAt))
      const evict = new Set(oldestFirst.slice(0, excess).map((entry) => entry.id))
      entries = entries.filter((entry) => entry.root !== root || !evict.has(entry.id) || protectedEntry(entry))
    }
    const answers = this.snapshot.answers.filter((answer) =>
      entries.some((entry) => entry.kind === "fact" && entry.id === answer.entryID && entry.version === answer.version && entry.status === "active" && !isExpired(entry, now)))
    this.snapshot = { schemaVersion: 1, entries, answers }
    await this.persist()
  }
}

const byRootCounts = (entries: readonly BlackboardEntry[]): ReadonlyMap<string, number> => {
  const counts = new Map<string, number>()
  for (const entry of entries) counts.set(entry.root, (counts.get(entry.root) ?? 0) + 1)
  return counts
}

/** Narrow parse of the service's TICK_DECIDED ledger payload (payload is unknown). */
export type RecentDecision = { readonly action: Action; readonly rationale: string; readonly root?: string; readonly sessionID: string; readonly decidedAt: ISO8601 }

export function parseTickDecided(record: LedgerRecord): RecentDecision | undefined {
  if (record.type !== "TICK_DECIDED") return undefined
  const payload = record.payload
  if (typeof payload !== "object" || payload === null) return undefined
  const { decision, root, sessionID } = payload as { decision?: unknown; root?: unknown; sessionID?: unknown }
  if (typeof decision !== "object" || decision === null || typeof sessionID !== "string") return undefined
  const { action, rationale } = decision as { action?: unknown; rationale?: unknown }
  if (typeof action !== "string" || typeof rationale !== "string") return undefined
  const known = ACTIONS.find((candidate) => candidate === action)
  if (known === undefined) return undefined
  return { action: known, rationale, ...(typeof root === "string" ? { root } : {}), sessionID, decidedAt: record.timestamp }
}
