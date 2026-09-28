// allow: SIZE_OK — implements the console channel + reply router (attention-queue
// contract §5 + Addendum A: correlation, dispositions, surfacing) as one cohesive
// module; the plan designates console.ts the channel implementation.
import { randomUUID } from "node:crypto"
import { existsSync } from "node:fs"
import { mkdir, readFile, rename, writeFile } from "node:fs/promises"
import { dirname } from "node:path"
import type { Ledger } from "./ledger"
import {
  AttentionQueue,
  DEFAULT_GRACE_MS,
  DEFAULT_TTL_MS,
  itemState,
  revalidate,
  selectNext,
  type ProposeInput,
  type RevalidationOutcome,
  type RevalidationSources,
} from "./queue"
import type {
  AttentionQueueItem,
  Citation,
  Decision,
  ISO8601,
  Message,
  QueueItemID,
  ResolutionDisposition,
  TargetRef,
} from "./types"

export const CHANNEL_ID = "console"
export const SKIP_SNOOZE_MS = 30 * 60 * 1000
const MAX_OPEN_ITEMS_PER_ROOT = 5

/**
 * Narrow structural view of the OpenCode client the channel needs. OpencodeClient
 * satisfies it structurally, so tests can stub it without casts.
 */
export type ConsoleClient = {
  createSession(directory: string, title: string): Promise<{ id: string; directory: string }>
  promptAsync(sessionID: string, directory: string, text: string): Promise<void>
  listMessages(sessionID: string, directory: string): Promise<readonly Message[]>
  toast(message: string, title: string): Promise<void>
}

export type ReplyInput =
  | { readonly kind: "text"; readonly text: string }
  | { readonly kind: "choice"; readonly index: number; readonly label?: string }
  | { readonly kind: "speech"; readonly transcript: string; readonly confidence?: number }

export type ReplyCorrelation =
  | { readonly status: "matched"; readonly itemID: QueueItemID }
  | { readonly status: "ambiguous"; readonly candidateItemIDs: readonly QueueItemID[] }
  | { readonly status: "unmatched" }

export type ReplyEvent = {
  readonly schemaVersion: 1
  readonly id: `reply_${string}`
  readonly receivedAt: ISO8601
  readonly channelID: string
  readonly root: string
  readonly presentationID?: string
  readonly contextTag?: string
  readonly explicitItemID?: QueueItemID
  readonly raw: ReplyInput
  readonly normalizedText: string
  readonly correlation: ReplyCorrelation
}

export type OperatorDisposition = "SKIP" | "HOLD" | "DND"

export type ConsoleState = {
  readonly consoles: Readonly<Record<string, string>>
  readonly counters: Readonly<Record<string, number>>
  readonly aliases: Readonly<Record<string, Readonly<Record<string, string>>>>
  readonly watermarks: Readonly<Record<string, string>>
  readonly held?: { readonly root: string; readonly itemID: QueueItemID }
  readonly dnd?: boolean
}

const EMPTY: ConsoleState = { consoles: {}, counters: {}, aliases: {}, watermarks: {} }

export type EscalationRequest = {
  readonly root: string
  readonly sessionID: string
  readonly question: string
  readonly rationale: string
  readonly citations: readonly Citation[]
  readonly confidence: number
  readonly target: TargetRef
}

export type ProposeOutcome =
  | { readonly kind: "enqueued"; readonly item: AttentionQueueItem }
  | { readonly kind: "deduped"; readonly item: AttentionQueueItem }
  | { readonly kind: "capped"; readonly reason: string }

export type SurfaceOutcome =
  | { readonly kind: "surfaced"; readonly item: AttentionQueueItem; readonly presentationID: string; readonly alias: string }
  | { readonly kind: "none" }
  | { readonly kind: "suppressed"; readonly reason: string }
  | { readonly kind: "resolved"; readonly disposition: ResolutionDisposition; readonly reason: string }

export type RouteOutcome =
  | { readonly kind: "propagation-pending"; readonly item: AttentionQueueItem; readonly reason: string }
  | { readonly kind: "resolved"; readonly disposition: ResolutionDisposition; readonly item: AttentionQueueItem }
  | { readonly kind: "disposition"; readonly disposition: OperatorDisposition; readonly item: AttentionQueueItem }
  | { readonly kind: "ambiguous"; readonly candidates: readonly QueueItemID[] }
  | { readonly kind: "unmatched" }
  | { readonly kind: "resumed" }

/** Options for handleReply when another channel reuses the shared reply router.
 *  channelID labels the ledger events; promptChoice=false suppresses the
 *  console-side "which item?" prompt (e.g. BeaconChannel re-presents via its own cards). */
export type HandleReplyOptions = {
  readonly channelID?: string
  readonly promptChoice?: boolean
}

const TICKET_PREFIX = /^q\d+\b\s*:?\s*/i
const ITEM_ID = /^(att_[a-z0-9]+)/i

const isQueueItemID = (value: string): value is QueueItemID => value.startsWith("att_")

const messageText = (message: Message): string =>
  message.parts.filter((part) => part.type === "text").map((part) => part.text ?? "").join("\n").trim()

const isSupervisorMessage = (text: string): boolean =>
  text.startsWith("[Supervisor]") || /^Q\d+ \[session /.test(text)

/** Remove only a recognized leading ticket prefix, preserving the answer body. */
export function stripTicketPrefix(text: string): string {
  return text.replace(TICKET_PREFIX, "").trim()
}

export function parseDisposition(text: string): OperatorDisposition | undefined {
  const normalized = stripTicketPrefix(text).toLowerCase()
  if (normalized === "skip" || normalized === "next") return "SKIP"
  if (normalized === "hold") return "HOLD"
  if (normalized === "dnd") return "DND"
  return undefined
}

/** Un-freeze command: clears HOLD/DND so a frozen channel can resume. */
export function isResume(text: string): boolean {
  return /^(resume|unhold|undnd|unpause)$/i.test(stripTicketPrefix(text))
}

/** GLANCE FORM headline for small-screen rendering (Addendum A: ≤60 chars). */
export function glanceHeadline(question: string): string {
  const single = question.replace(/\s+/g, " ").trim()
  return single.length <= 60 ? single : `${single.slice(0, 57)}...`
}

export type CorrelationContext = {
  readonly root: string
  readonly surfacedItemID?: QueueItemID
  readonly surfacedItemRoot?: string
  readonly unresolvedItemIDs: readonly QueueItemID[]
  readonly resolveAlias: (token: string) => QueueItemID | undefined
}

/** §5 correlation: explicit Q<n>/item id wins; bare answer only when unambiguous. */
export function correlateReply(text: string, context: CorrelationContext): ReplyCorrelation {
  const trimmed = text.trim()
  const aliasMatch = /^q(\d+)\b/i.exec(trimmed)
  if (aliasMatch !== null) {
    const itemID = context.resolveAlias(`Q${aliasMatch[1]}`)
    if (itemID === undefined || !context.unresolvedItemIDs.includes(itemID)) return { status: "unmatched" }
    return { status: "matched", itemID }
  }
  const idMatch = ITEM_ID.exec(trimmed)
  if (idMatch !== null) {
    const candidate = idMatch[1]
    if (candidate !== undefined && isQueueItemID(candidate) && context.unresolvedItemIDs.includes(candidate)) {
      return { status: "matched", itemID: candidate }
    }
    return { status: "unmatched" }
  }
  if (context.surfacedItemID !== undefined && context.surfacedItemRoot === context.root) return { status: "matched", itemID: context.surfacedItemID }
  if (context.unresolvedItemIDs.length === 1) {
    const only = context.unresolvedItemIDs[0]
    if (only !== undefined) return { status: "matched", itemID: only }
  }
  if (context.unresolvedItemIDs.length === 0) return { status: "unmatched" }
  return { status: "ambiguous", candidateItemIDs: context.unresolvedItemIDs }
}

function dispositionFor(outcome: RevalidationOutcome): ResolutionDisposition | undefined {
  switch (outcome.kind) {
    case "retired-by-evidence":
      return "retired-by-evidence"
    case "superseded":
    case "materially-changed":
      return "superseded"
    case "expired":
      return "expired"
    case "valid":
    case "temporarily-invalid":
    case "re-decide":
    case "downgrade-console-only":
      return undefined
  }
}

export function projectBasename(root: string): string {
  return root.split("/").at(-1) ?? root
}

export function sessionLabel(item: AttentionQueueItem): string {
  // Human-oriented: session TITLE first; the raw ID is for logs, not for people.
  return item.target.sessionTitle ?? `session ${item.target.sessionID.slice(0, 14)}`
}

export function formatTicket(alias: string, item: AttentionQueueItem): string {
  const session = sessionLabel(item)
  const project = projectBasename(item.target.root)
  const citations = item.origin.citations
    .map((citation) => `${citation.session}/${citation.messageID}: ${citation.quote.slice(0, 80)}`)
    .join("; ")
  // First line MUST carry the [Supervisor] tag: the ticket is written into the
  // console session as a user message, and pollReplies filters supervisor-authored
  // turns by that prefix. Un-tagged tickets are read back as operator replies and
  // propagated into worker sessions (2026-09-28 self-echo regression).
  return [
    `[Supervisor] ${alias} — ${session} [${project}]`,
    glanceHeadline(item.question),
    "",
    item.question,
    "",
    `Why: ${item.rationale.slice(0, 400)}`,
    ...(citations === "" ? [] : [`Citations: ${citations}`]),
    "",
    `Reply in this session, e.g. "${alias}: <your answer>".`,
  ].join("\n")
}

/**
 * Console channel over the AttentionQueue. It presents the scheduler's selected
 * item, collects correlated replies, and routes outcomes; it never owns ticket
 * truth (the queue does) and never writes into worker sessions.
 */
export type ConsoleChannelOptions = {
  readonly client: ConsoleClient
  readonly queue: AttentionQueue
  readonly statePath: string
  readonly ledger: () => Ledger
  readonly setLedger: (next: Ledger) => void
  readonly probe: (item: AttentionQueueItem) => Promise<RevalidationSources>
  readonly deliverPropagation?: (input: { root: string; sessionID: string; answer: string; ticketID: QueueItemID }) => Promise<boolean>
}

export class ConsoleChannel {
  private state: ConsoleState = EMPTY
  private readonly client: ConsoleClient
  private readonly queue: AttentionQueue
  private readonly statePath: string
  private readonly ledger: () => Ledger
  private readonly setLedger: (next: Ledger) => void
  private readonly probe: (item: AttentionQueueItem) => Promise<RevalidationSources>
  private readonly deliverPropagation: ((input: { root: string; sessionID: string; answer: string; ticketID: QueueItemID }) => Promise<boolean>) | undefined

  constructor(options: ConsoleChannelOptions) {
    this.client = options.client
    this.queue = options.queue
    this.statePath = options.statePath
    this.ledger = options.ledger
    this.setLedger = options.setLedger
    this.probe = options.probe
    this.deliverPropagation = options.deliverPropagation
  }

  get held(): { readonly root: string; readonly itemID: QueueItemID } | undefined {
    return this.state.held
  }

  get dnd(): boolean {
    return this.state.dnd === true
  }

  async load(): Promise<void> {
    if (!existsSync(this.statePath)) return
    const parsed = JSON.parse(await readFile(this.statePath, "utf8")) as Partial<ConsoleState>
    this.state = {
      consoles: parsed.consoles ?? {},
      counters: parsed.counters ?? {},
      aliases: parsed.aliases ?? {},
      watermarks: parsed.watermarks ?? {},
      ...(parsed.held === undefined ? {} : { held: parsed.held }),
      ...(parsed.dnd === undefined ? {} : { dnd: parsed.dnd }),
    }
  }

  sessionID(root: string): string | undefined {
    return this.state.consoles[root]
  }

  allSessionIDs(): ReadonlySet<string> {
    return new Set(Object.values(this.state.consoles))
  }

  /** Find-or-create the per-root console; on first creation send an intro turn. */
  async ensure(root: string, title: string): Promise<string | undefined> {
    const existing = this.state.consoles[root]
    if (existing !== undefined) return existing
    try {
      const session = await this.client.createSession(root, title)
      this.state = { ...this.state, consoles: { ...this.state.consoles, [root]: session.id } }
      await this.persist()
      this.setLedger(await this.ledger().append("CONSOLE_INITIALIZED", { root, sessionID: session.id }))
      await this.client.promptAsync(
        session.id,
        root,
        "[Supervisor] console initialized. Escalations for this project appear here as numbered tickets (Q1, Q2, ...). Everything else the supervisor does stays read-only. Your replies are recorded in the audit ledger; automated ticket resolution arrives in a later phase.",
      )
      return session.id
    } catch (error) {
      if (error instanceof Error) {
        this.setLedger(await this.ledger().append("ERROR", { root, reason: `console ensure failed: ${error.message}` }))
      }
      return undefined
    }
  }

  /** ESCALATE write path: enqueue into the queue (replaces openTicket). */
  async proposeEscalation(request: EscalationRequest): Promise<ProposeOutcome> {
    const open = this.queue.items.filter((item) => item.target.root === request.root && itemState(item) !== "resolved")
    if (open.length >= MAX_OPEN_ITEMS_PER_ROOT) {
      return { kind: "capped", reason: `root at open-item cap (${MAX_OPEN_ITEMS_PER_ROOT})` }
    }
    const now = new Date().toISOString()
    const decision: Decision = { action: "ESCALATE", rationale: request.rationale, citations: request.citations, confidence: request.confidence }
    const input: ProposeInput = {
      kind: "decision",
      origin: {
        tickID: `tick_${randomUUID().replace(/-/g, "").slice(0, 16)}`,
        ledgerSeq: this.ledger().records.length,
        decision,
        citations: request.citations,
        informationNeeds: [],
        contextDigest: request.rationale.slice(0, 200),
      },
      target: request.target,
      actionClass: "ESCALATE",
      escalationKind: "DECISION",
      question: request.question,
      rationale: request.rationale,
      priority: { stakes: 4, urgency: 4, confidence: request.confidence, freshness: 1, createdAt: now },
      premises: [
        { id: `p_${randomUUID().replace(/-/g, "").slice(0, 8)}`, kind: "session-idle", sessionID: request.sessionID, observedAt: now },
        {
          id: `p_${randomUUID().replace(/-/g, "").slice(0, 8)}`,
          kind: "no-newer-turn",
          sessionID: request.sessionID,
          latestMessageID: request.target.assistantMessageID ?? request.target.userMessageID,
          observedAt: now,
        },
      ],
    }
    const result = await this.queue.propose(input)
    if (result.kind === "blocked") return { kind: "capped", reason: result.reason }
    return result.kind === "deduped" ? { kind: "deduped", item: result.item } : { kind: "enqueued", item: result.item }
  }

  /** Revalidate → select → acquire lease → present. Never surfaces without revalidation. */
  async surfaceNext(root: string, now: ISO8601): Promise<SurfaceOutcome> {
    if (this.state.dnd === true) return { kind: "suppressed", reason: "DND global freeze" }
    if (this.state.held?.root === root) return { kind: "suppressed", reason: "HOLD freeze on this channel" }
    const activeLease = this.queue.lease
    const refreshable = this.queue.items.filter((item) => {
      if (item.target.root !== root) return false
      const state = itemState(item)
      if (state === "proposed" || state === "revalidated") return true
      return state === "surfaced" && (activeLease === undefined || activeLease.itemID !== item.id)
    })
    let resolved: { readonly disposition: ResolutionDisposition; readonly reason: string } | undefined
    for (const candidate of refreshable) {
      const sources = await this.probe(candidate)
      const result = await this.queue.revalidate(candidate.id, sources, { now, graceMs: DEFAULT_GRACE_MS, ttlMs: DEFAULT_TTL_MS })
      if (result.outcome.kind !== "valid") {
        const disposition = dispositionFor(result.outcome)
        if (disposition !== undefined) resolved = { disposition, reason: result.outcome.reason }
      }
    }
    const candidates = this.queue.items.filter((item) => item.target.root === root)
    const item = selectNext({ items: candidates, lease: this.queue.lease, surfaceLog: [], now })
    if (item === undefined) return resolved === undefined ? { kind: "none" } : { kind: "resolved", ...resolved }
    const lease = await this.queue.acquireLease(item.id, { channelID: CHANNEL_ID, now })
    if (lease.kind !== "acquired") return { kind: "suppressed", reason: lease.reason }
    const consoleID = await this.ensure(root, `[Supervisor] ${root.split("/").at(-1) ?? root}`)
    if (consoleID === undefined) {
      await this.queue.defer(lease.lease.presentationID, now, now)
      return { kind: "suppressed", reason: "console unavailable" }
    }
    const alias = await this.assignAlias(root, item.id)
    await this.client.promptAsync(consoleID, root, formatTicket(alias, item))
    await this.client.toast(`${projectBasename(root)} — ${sessionLabel(item)}: ${glanceHeadline(item.question)}`, `[Supervisor] ${projectBasename(root)}`)
    return { kind: "surfaced", item, presentationID: lease.lease.presentationID, alias }
  }

  aliasTable(): Readonly<Record<string, Readonly<Record<string, string>>>> {
    return this.state.aliases
  }

  /** Poll the root's console for new operator turns; first observation sets the watermark. */
  async pollReplies(root: string, now: ISO8601): Promise<readonly ReplyEvent[]> {
    const consoleID = this.state.consoles[root]
    if (consoleID === undefined) return []
    const messages = await this.client.listMessages(consoleID, root)
    const last = messages.at(-1)
    const watermark = this.state.watermarks[consoleID]
    if (watermark === undefined) {
      if (last !== undefined) await this.setWatermark(consoleID, last.id)
      return []
    }
    const start = messages.findIndex((message) => message.id === watermark)
    const fresh = start === -1 ? messages : messages.slice(start + 1)
    const replies: ReplyEvent[] = []
    for (const message of fresh) {
      if (message.role !== "user") continue
      const text = messageText(message)
      if (text === "" || isSupervisorMessage(text)) continue
      replies.push(this.buildReply(root, text, now))
    }
    if (last !== undefined && last.id !== watermark) await this.setWatermark(consoleID, last.id)
    return replies
  }

  /** Crash recovery: items left in `answered` (service killed mid-routing) re-enter
   *  the router's tail: revalidate → resolve or propagation-pending. Idempotent. */
  async recoverAnswered(): Promise<number> {
    const answered = this.queue.items.filter((item) => itemState(item) === "answered")
    let recovered = 0
    for (const item of answered) {
      const now = new Date().toISOString()
      try {
        const sources = await this.probe(item)
        const outcome = revalidate(item, sources, { now, graceMs: DEFAULT_GRACE_MS, ttlMs: DEFAULT_TTL_MS })
        if (outcome.kind === "retired-by-evidence") {
          await this.queue.resolve(item.id, { disposition: "retired-by-evidence", evidence: outcome.evidence, now, reason: outcome.reason })
        } else if (outcome.kind === "superseded" || outcome.kind === "materially-changed" || outcome.kind === "re-decide") {
          await this.queue.resolve(item.id, { disposition: "superseded", evidence: [], now, reason: outcome.reason })
        } else if (outcome.kind === "expired") {
          await this.queue.resolve(item.id, { disposition: "expired", evidence: [], now, reason: outcome.reason })
        } else {
          this.setLedger(await this.ledger().append("QUEUE_PROPAGATION_PROPOSED", {
            itemID: item.id,
            target: item.target,
            answer: "(recovered after restart — reply was applied before the crash)",
            mode: "pending",
            reason: "reason" in outcome ? outcome.reason : "still relevant",
          }))
        }
        recovered += 1
      } catch (error) {
        this.setLedger(await this.ledger().append("ERROR", { itemID: item.id, error: `recoverAnswered failed: ${error instanceof Error ? error.message : String(error)}` }))
      }
    }
    return recovered
  }

  /** Correlate → mark answered → revalidate → route. Never guesses on ambiguity.
   *  Shared reply-router: BeaconChannel routes its replies through this method
   *  with { channelID: "beacon", promptChoice: false } (Seam 4, Amendment 2026-09-25). */
  async handleReply(reply: ReplyEvent, now: ISO8601, options: HandleReplyOptions = {}): Promise<RouteOutcome> {
    const channelID = options.channelID ?? CHANNEL_ID
    if (isResume(reply.normalizedText)) {
      this.state = { consoles: this.state.consoles, counters: this.state.counters, aliases: this.state.aliases, watermarks: this.state.watermarks, dnd: false }
      await this.persist()
      this.setLedger(await this.ledger().append("QUEUE_REPLY_RECEIVED", { replyEventID: reply.id, channelID, action: "resume" }))
      return { kind: "resumed" }
    }
    if (reply.correlation.status === "ambiguous") {
      this.setLedger(await this.ledger().append("QUEUE_REPLY_AMBIGUOUS", { replyEventID: reply.id, root: reply.root, channelID, candidates: reply.correlation.candidateItemIDs }))
      if (options.promptChoice !== false) await this.requestChoice(reply)
      return { kind: "ambiguous", candidates: reply.correlation.candidateItemIDs }
    }
    if (reply.correlation.status === "unmatched") {
      this.setLedger(await this.ledger().append("QUEUE_REPLY_AMBIGUOUS", { replyEventID: reply.id, root: reply.root, channelID, reason: "no item correlates" }))
      return { kind: "unmatched" }
    }
    const itemID = reply.correlation.itemID
    const current = this.queue.items.find((entry) => entry.id === itemID)
    if (current === undefined || itemState(current) === "resolved" || itemState(current) === "answered") {
      this.setLedger(await this.ledger().append("QUEUE_REPLY_AMBIGUOUS", { replyEventID: reply.id, root: reply.root, channelID, reason: "item is already terminal" }))
      return { kind: "unmatched" }
    }
    const disposition = parseDisposition(reply.normalizedText)
    if (disposition !== undefined) return this.applyDisposition(disposition, itemID, reply, now)
    const answered = await this.queue.markAnswered(itemID, reply.id, channelID, now)
    const lease = this.queue.lease
    if (lease !== undefined && lease.itemID === itemID) await this.queue.defer(lease.presentationID, now, now)
    const sources = await this.probe(answered)
    const outcome = revalidate(answered, sources, { now, graceMs: DEFAULT_GRACE_MS, ttlMs: DEFAULT_TTL_MS })
    if (outcome.kind === "retired-by-evidence") {
      const item = await this.queue.resolve(itemID, { disposition: "retired-by-evidence", evidence: outcome.evidence, now, reason: outcome.reason })
      return { kind: "resolved", disposition: "retired-by-evidence", item }
    }
    if (outcome.kind === "superseded" || outcome.kind === "materially-changed" || outcome.kind === "re-decide") {
      const item = await this.queue.resolve(itemID, { disposition: "superseded", evidence: [], now, reason: outcome.reason })
      return { kind: "resolved", disposition: "superseded", item }
    }
    if (outcome.kind === "expired") {
      const item = await this.queue.resolve(itemID, { disposition: "expired", evidence: [], now, reason: outcome.reason })
      return { kind: "resolved", disposition: "expired", item }
    }
    const reason = outcome.kind === "valid" ? "still relevant" : "reason" in outcome ? outcome.reason : "still relevant"
    if (this.deliverPropagation !== undefined) {
      const delivered = await this.deliverPropagation({
        root: answered.target.root,
        sessionID: answered.target.sessionID,
        answer: reply.normalizedText,
        ticketID: itemID,
      })
      if (delivered) {
        const item = await this.queue.resolve(itemID, { disposition: "propagated", evidence: [], now, reason: "operator answer delivered to worker session" })
        return { kind: "resolved", disposition: "propagated", item }
      }
    }
    this.setLedger(await this.ledger().append("QUEUE_PROPAGATION_PROPOSED", {
      itemID,
      replyEventID: reply.id,
      target: answered.target,
      answer: reply.normalizedText,
      mode: "pending",
      reason,
    }))
    return { kind: "propagation-pending", item: answered, reason }
  }

  private async applyDisposition(disposition: OperatorDisposition, itemID: QueueItemID, reply: ReplyEvent, now: ISO8601): Promise<RouteOutcome> {
    const item = this.queue.items.find((entry) => entry.id === itemID)
    if (item === undefined) return { kind: "unmatched" }
    this.setLedger(await this.ledger().append("QUEUE_REPLY_RECEIVED", { itemID, replyEventID: reply.id, channelID: CHANNEL_ID, disposition }))
    if (disposition === "SKIP") {
      const lease = this.queue.lease
      if (lease !== undefined && lease.itemID === itemID) {
        await this.queue.defer(lease.presentationID, new Date(Date.parse(now) + SKIP_SNOOZE_MS).toISOString(), now)
      }
      return { kind: "disposition", disposition, item }
    }
    if (disposition === "HOLD") {
      this.state = { ...this.state, held: { root: item.target.root, itemID } }
      await this.persist()
      return { kind: "disposition", disposition, item }
    }
    this.state = { ...this.state, dnd: true }
    await this.persist()
    return { kind: "disposition", disposition, item }
  }

  private buildReply(root: string, text: string, now: ISO8601): ReplyEvent {
    const lease = this.queue.lease
    const surfacedItem = lease === undefined ? undefined : this.queue.items.find((item) => item.id === lease.itemID)
    const unresolved = this.queue.items
      .filter((item) => item.target.root === root && itemState(item) !== "resolved" && itemState(item) !== "answered")
      .map((item) => item.id)
    const aliases = this.state.aliases[root] ?? {}
    const correlation = correlateReply(text, {
      root,
      ...(lease === undefined || surfacedItem === undefined ? {} : { surfacedItemID: lease.itemID, surfacedItemRoot: surfacedItem.target.root }),
      unresolvedItemIDs: unresolved,
      resolveAlias: (token) => {
        const itemID = aliases[token]
        return itemID !== undefined && isQueueItemID(itemID) ? itemID : undefined
      },
    })
    return {
      schemaVersion: 1,
      id: `reply_${randomUUID().replace(/-/g, "").slice(0, 16)}`,
      receivedAt: now,
      channelID: CHANNEL_ID,
      root,
      ...(lease === undefined ? {} : { presentationID: lease.presentationID }),
      raw: { kind: "text", text },
      normalizedText: stripTicketPrefix(text),
      correlation,
    }
  }

  private async requestChoice(reply: ReplyEvent): Promise<void> {
    const consoleID = this.state.consoles[reply.root]
    if (consoleID === undefined) return
    const candidates = reply.correlation.status === "ambiguous" ? reply.correlation.candidateItemIDs : []
    const lines = candidates.map((id, index) => {
      const item = this.queue.items.find((entry) => entry.id === id)
      return `${index + 1}. ${item?.question ?? id}`
    })
    await this.client.promptAsync(consoleID, reply.root, `[Supervisor] Ambiguous reply — which item? Reply with Q<n>:\n${lines.join("\n")}`)
  }

  private async assignAlias(root: string, itemID: QueueItemID): Promise<string> {
    const aliases = this.state.aliases[root] ?? {}
    const existing = Object.entries(aliases).find(([, id]) => id === itemID)
    if (existing !== undefined) return existing[0]
    const n = (this.state.counters[root] ?? 0) + 1
    const alias = `Q${n}`
    this.state = {
      ...this.state,
      counters: { ...this.state.counters, [root]: n },
      aliases: { ...this.state.aliases, [root]: { ...aliases, [alias]: itemID } },
    }
    await this.persist()
    return alias
  }

  private async setWatermark(consoleID: string, messageID: string): Promise<void> {
    this.state = { ...this.state, watermarks: { ...this.state.watermarks, [consoleID]: messageID } }
    await this.persist()
  }

  private async persist(): Promise<void> {
    const temporary = `${this.statePath}.tmp`
    await mkdir(dirname(this.statePath), { recursive: true })
    await writeFile(temporary, JSON.stringify(this.state, null, 2))
    await rename(temporary, this.statePath)
  }
}
