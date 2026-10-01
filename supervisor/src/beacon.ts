// allow: SIZE_OK — implements the OC Beacon answer-capture channel (Seam 4,
// Amendment 2026-09-25): per-root reply-inbox session polling, envelope
// parsing, clientMessageID dedup, correlation. Presents nothing; routing goes
// through the shared reply-router (ConsoleChannel.handleReply), the queue
// stays the single writer.
import { randomUUID } from "node:crypto"
import { existsSync } from "node:fs"
import { mkdir, readFile, rename, writeFile } from "node:fs/promises"
import { dirname } from "node:path"
import { correlateReply, projectBasename, stripTicketPrefix, type HandleReplyOptions, type ReplyCorrelation, type ReplyEvent, type ReplyInput, type RouteOutcome } from "./console"
import { itemState, type AttentionQueue } from "./queue"
import type { ISO8601, Message, QueueItemID, Session } from "./types"

export const BEACON_CHANNEL_ID = "beacon"
export const INBOX_TITLE_PREFIX = "[Beacon replies] "
const PROCESSED_CAP = 1000

/**
 * Narrow structural view of the OpenCode client the channel needs (read-only:
 * the Beacon app creates the inbox sessions; the supervisor never prompts into
 * them — it presents nothing per Addendum A).
 */
export type BeaconClient = {
  listSessions(directory: string): Promise<readonly Session[]>
  listMessages(sessionID: string, directory: string, limit?: number): Promise<readonly Message[]>
}

/** Envelope shape per the contract (Amendment 2026-09-25, `v: 1`). */
export type BeaconEnvelope = {
  readonly v: 1
  readonly clientMessageID: string
  readonly kind: "text" | "choice" | "speech"
  readonly text?: string
  readonly index?: number
  readonly contextTag?: string
  readonly explicitItemID?: string
}

export type BeaconState = {
  readonly inboxes: Readonly<Record<string, string>>
  readonly watermarks: Readonly<Record<string, string>>
  readonly processedClientMessageIDs: readonly string[]
}

const EMPTY: BeaconState = { inboxes: {}, watermarks: {}, processedClientMessageIDs: [] }

export type BeaconChannelOptions = {
  readonly client: BeaconClient
  readonly queue: AttentionQueue
  readonly statePath: string
  /** Per-root alias table from the console channel state (consoles.json). */
  readonly aliases: () => Readonly<Record<string, Readonly<Record<string, string>>>>
  /** The live reply-router (ConsoleChannel.handleReply) with beacon options bound. */
  readonly route: (reply: ReplyEvent, now: ISO8601, options?: HandleReplyOptions) => Promise<RouteOutcome>
}

/** Parse a whole-message JSON envelope; returns undefined for plain text. */
export function parseEnvelope(messageText: string): BeaconEnvelope | undefined {
  const trimmed = messageText.trim()
  if (!trimmed.startsWith("{") || !trimmed.endsWith("}")) return undefined
  let parsed: unknown
  try {
    parsed = JSON.parse(trimmed)
  } catch {
    return undefined
  }
  if (typeof parsed !== "object" || parsed === null) return undefined
  const candidate = parsed as Record<string, unknown>
  if (candidate["v"] !== 1) return undefined
  const clientMessageID = candidate["clientMessageID"]
  if (typeof clientMessageID !== "string" || clientMessageID === "") return undefined
  const kind = candidate["kind"]
  if (kind !== "text" && kind !== "choice" && kind !== "speech") return undefined
  const text = candidate["text"]
  if (text !== undefined && typeof text !== "string") return undefined
  const index = candidate["index"]
  if (index !== undefined && typeof index !== "number") return undefined
  const contextTag = candidate["contextTag"]
  if (contextTag !== undefined && typeof contextTag !== "string") return undefined
  const explicitItemID = candidate["explicitItemID"]
  if (explicitItemID !== undefined && typeof explicitItemID !== "string") return undefined
  return {
    v: 1,
    clientMessageID,
    kind,
    ...(text === undefined ? {} : { text }),
    ...(index === undefined ? {} : { index }),
    ...(contextTag === undefined ? {} : { contextTag }),
    ...(explicitItemID === undefined ? {} : { explicitItemID }),
  }
}

const isQueueItemID = (value: string): value is QueueItemID => value.startsWith("att_")

export function inboxTitle(root: string): string {
  return `${INBOX_TITLE_PREFIX}${projectBasename(root)}`
}

/**
 * OC Beacon answer capture (AMBIENT/VISUAL channel class): polls the per-root
 * `[Beacon replies] <basename(root)>` inbox sessions, dedups by
 * clientMessageID, correlates (explicitItemID → contextTag → Q<n> alias →
 * standard §5 rules), and routes every consumed reply through the shared
 * reply-router. Correlates to nothing ⇒ the router records
 * QUEUE_REPLY_AMBIGUOUS — no guessing. Presents nothing anywhere.
 */
export class BeaconChannel {
  private state: BeaconState = EMPTY
  private readonly client: BeaconClient
  private readonly queue: AttentionQueue
  private readonly statePath: string
  private readonly aliases: () => Readonly<Record<string, Readonly<Record<string, string>>>>
  private readonly route: (reply: ReplyEvent, now: ISO8601, options?: HandleReplyOptions) => Promise<RouteOutcome>

  constructor(options: BeaconChannelOptions) {
    this.client = options.client
    this.queue = options.queue
    this.statePath = options.statePath
    this.aliases = options.aliases
    this.route = options.route
  }

  async load(): Promise<void> {
    if (!existsSync(this.statePath)) return
    const parsed = JSON.parse(await readFile(this.statePath, "utf8")) as Partial<BeaconState>
    this.state = {
      inboxes: parsed.inboxes ?? {},
      watermarks: parsed.watermarks ?? {},
      processedClientMessageIDs: Array.isArray(parsed.processedClientMessageIDs)
        ? parsed.processedClientMessageIDs.filter((entry): entry is string => typeof entry === "string").slice(-PROCESSED_CAP)
        : [],
    }
  }

  /** Inbox session IDs — consumed by the service to exclude them from supervision. */
  allSessionIDs(): ReadonlySet<string> {
    return new Set(Object.values(this.state.inboxes))
  }

  inboxSessionID(root: string): string | undefined {
    return this.state.inboxes[root]
  }

  /** Correlate → route. Beacon adds nothing on top of the shared router. */
  async handleReply(reply: ReplyEvent, now: ISO8601): Promise<RouteOutcome> {
    return this.route(reply, now, { channelID: BEACON_CHANNEL_ID, promptChoice: false })
  }

  /** Poll the root's reply-inbox session; first observation sets the watermark. */
  async poll(root: string, now: ISO8601): Promise<readonly ReplyEvent[]> {
    const inboxID = await this.ensureInbox(root)
    if (inboxID === undefined) return []
    // Tail-fetch (limit 50): same firehose rationale as console.pollReplies.
    let messages = await this.client.listMessages(inboxID, root, 50)
    let last = messages.at(-1)
    const watermark = this.state.watermarks[inboxID]
    if (watermark === undefined) {
      if (last !== undefined) await this.setWatermark(inboxID, last.id)
      return []
    }
    if (!messages.some((message) => message.id === watermark)) {
      messages = await this.client.listMessages(inboxID, root)
      last = messages.at(-1)
    }
    const start = messages.findIndex((message) => message.id === watermark)
    const fresh = start === -1 ? messages : messages.slice(start + 1)
    const replies: ReplyEvent[] = []
    for (const message of fresh) {
      if (message.role !== "user") continue
      const text = messageText(message)
      if (text === "") continue
      const envelope = parseEnvelope(text)
      if (envelope !== undefined) {
        if (this.state.processedClientMessageIDs.includes(envelope.clientMessageID)) continue
        await this.recordProcessed(envelope.clientMessageID)
      }
      replies.push(this.buildReply(root, text, envelope, now))
    }
    if (last !== undefined && last.id !== watermark) await this.setWatermark(inboxID, last.id)
    return replies
  }

  /** Resolution order per the contract: explicitItemID → contextTag → §5 rules (alias, surfaced, single/ambiguous). */
  private buildReply(root: string, text: string, envelope: BeaconEnvelope | undefined, now: ISO8601): ReplyEvent {
    const lease = this.queue.lease
    const surfacedItem = lease === undefined ? undefined : this.queue.items.find((item) => item.id === lease.itemID)
    const unresolved = this.queue.items
      .filter((item) => item.target.root === root && itemState(item) !== "resolved" && itemState(item) !== "answered")
      .map((item) => item.id)
    const raw = rawInput(envelope, text)
    let correlation: ReplyCorrelation | undefined
    const explicit = envelope?.explicitItemID
    if (explicit !== undefined) {
      // explicitItemID wins — even for terminal/unknown ids (the router records
      // those as QUEUE_REPLY_AMBIGUOUS "item is already terminal", never re-routes).
      correlation = isQueueItemID(explicit) ? { status: "matched", itemID: explicit } : { status: "unmatched" }
    }
    if (correlation === undefined && envelope?.contextTag !== undefined && lease !== undefined && lease.presentationID === envelope.contextTag) {
      correlation = { status: "matched", itemID: lease.itemID }
    }
    if (correlation === undefined) {
      const normalized = stripTicketPrefix(envelope?.text ?? text)
      const aliases = this.aliases()[root] ?? {}
      correlation = correlateReply(normalized, {
        root,
        ...(lease === undefined || surfacedItem === undefined ? {} : { surfacedItemID: lease.itemID, surfacedItemRoot: surfacedItem.target.root }),
        unresolvedItemIDs: unresolved,
        resolveAlias: (token) => {
          const itemID = aliases[token]
          return itemID !== undefined && isQueueItemID(itemID) ? itemID : undefined
        },
      })
    }
    return {
      schemaVersion: 1,
      id: `reply_${randomUUID().replace(/-/g, "").slice(0, 16)}`,
      receivedAt: now,
      channelID: BEACON_CHANNEL_ID,
      root,
      ...(lease === undefined ? {} : { presentationID: lease.presentationID }),
      ...(envelope?.contextTag === undefined ? {} : { contextTag: envelope.contextTag }),
      ...(explicit !== undefined && isQueueItemID(explicit) ? { explicitItemID: explicit } : {}),
      raw,
      normalizedText: stripTicketPrefix(envelope?.text ?? text),
      correlation,
    }
  }

  /** Find the root's inbox session by title convention (created by the app on first reply). */
  private async ensureInbox(root: string): Promise<string | undefined> {
    const cached = this.state.inboxes[root]
    if (cached !== undefined) return cached
    const sessions = await this.client.listSessions(root)
    const inbox = sessions.find((session) => session.title?.startsWith(INBOX_TITLE_PREFIX) === true)
    if (inbox === undefined) return undefined
    this.state = { ...this.state, inboxes: { ...this.state.inboxes, [root]: inbox.id } }
    await this.persist()
    return inbox.id
  }

  private async recordProcessed(clientMessageID: string): Promise<void> {
    const next = [...this.state.processedClientMessageIDs, clientMessageID].slice(-PROCESSED_CAP)
    this.state = { ...this.state, processedClientMessageIDs: next }
    await this.persist()
  }

  private async setWatermark(inboxID: string, messageID: string): Promise<void> {
    this.state = { ...this.state, watermarks: { ...this.state.watermarks, [inboxID]: messageID } }
    await this.persist()
  }

  private async persist(): Promise<void> {
    const temporary = `${this.statePath}.tmp`
    await mkdir(dirname(this.statePath), { recursive: true })
    await writeFile(temporary, JSON.stringify(this.state, null, 2))
    await rename(temporary, this.statePath)
  }
}

function rawInput(envelope: BeaconEnvelope | undefined, text: string): ReplyInput {
  if (envelope === undefined) return { kind: "text", text }
  switch (envelope.kind) {
    case "choice":
      return { kind: "choice", index: envelope.index ?? 0, ...(envelope.text === undefined ? {} : { label: envelope.text }) }
    case "speech":
      return { kind: "speech", transcript: envelope.text ?? "" }
    case "text":
      return { kind: "text", text: envelope.text ?? text }
  }
}

function messageText(message: Message): string {
  return message.parts.filter((part) => part.type === "text").map((part) => part.text ?? "").join("\n").trim()
}

