// allow: SIZE_OK — implements the normative attention-queue contract (spec §1–4: schemas,
// lifecycle state machine, prioritization, revalidation matrix, poison handling, persistence)
// as one cohesive module; the plan designates queue.ts the largest single supervisor module.
import { createHash, randomUUID } from "node:crypto"
import { mkdir, readFile, rename, writeFile } from "node:fs/promises"
import { dirname } from "node:path"
import type {
  Action,
  AttentionQueueItem,
  Citation,
  DecisionKey,
  EscalationKind,
  EvidenceRef,
  ISO8601,
  LedgerRecordType,
  LifecycleEvent,
  OriginTick,
  Premise,
  PresentationLease,
  QueueItemID,
  QueueKind,
  QueuePriorityInputs,
  QueueSnapshot,
  ResolutionDisposition,
  SurfaceRecord,
  TargetRef,
} from "./types"

export const QUEUE_SCHEMA_VERSION = 1
export const BAND_B_MIN_SCORE = 40
export const BAND_C_MIN_SCORE = 15
export const FRESHNESS_HALF_LIFE_HOURS = 6
export const DEFAULT_GRACE_MS = 60_000
export const DEFAULT_TTL_MS = 24 * 60 * 60 * 1000
export const LEASE_TTL_MS = 5 * 60 * 1000
export const POISON_SUSPECT_THRESHOLD = 3
export const POISON_EXPIRE_THRESHOLD = 4
export const MAX_CONSECUTIVE_ROOT_SURFACES = 2
export const SURFACE_LOG_CAP = 500
export const REDECIDE_HIGH_WATER = 4

const HOUR_MS = 3_600_000

const hoursBetween = (from: ISO8601, to: ISO8601): number => Math.max(0, (Date.parse(to) - Date.parse(from)) / HOUR_MS)

/** Time-sortable item identity (spec §7.1: UUIDv7 or equivalent). */
const timeSortableID = (): string => `${Date.now().toString(36)}${randomUUID().replace(/-/g, "").slice(0, 12)}`

/** Strip ticket numbers, timestamps, and whitespace variation so cross-tick subjects collapse. */
export function normalizeSubject(subject: string): string {
  return subject
    .toLowerCase()
    .replace(/\bq\d+\b\s*:?/g, " ")
    .replace(/\d{4}-\d{2}-\d{2}t[\d:.]+z?/g, " ")
    .replace(/\s+/g, " ")
    .trim()
}

export function decisionKey(input: {
  readonly root: string
  readonly sessionID: string
  readonly actionClass: Action
  readonly escalationKind?: EscalationKind
  readonly subject: string
}): DecisionKey {
  const parts = [input.root, input.sessionID, input.actionClass, input.escalationKind ?? "none", normalizeSubject(input.subject)]
  return createHash("sha256").update(parts.join("\u0000")).digest("hex")
}

export type QueueItemState = "proposed" | "revalidated" | "surfaced" | "answered" | "resolved"

export function itemState(item: AttentionQueueItem): QueueItemState {
  const last = item.lifecycle.at(-1)
  return last === undefined ? "proposed" : last.state
}

export function lastRevalidation(item: AttentionQueueItem): "valid" | "temporarily-invalid" | "materially-changed" | undefined {
  for (let index = item.lifecycle.length - 1; index >= 0; index -= 1) {
    const event = item.lifecycle[index]
    if (event !== undefined && event.state === "revalidated") return event.result
  }
  return undefined
}

export function recomputeFreshness(item: AttentionQueueItem, now: ISO8601): number {
  return Math.pow(0.5, hoursBetween(item.priority.createdAt, now) / FRESHNESS_HALF_LIFE_HOURS)
}

export function scoreItem(item: AttentionQueueItem, now: ISO8601): number {
  const waitingHours = hoursBetween(item.priority.createdAt, now)
  const waitingBoost = Math.min(2.0, 1 + Math.log2(1 + waitingHours) / 4)
  const uncertainty = 0.75 + 0.25 * (1 - item.priority.confidence)
  return item.priority.stakes * item.priority.urgency * waitingBoost * recomputeFreshness(item, now) * uncertainty
}

export type PriorityBand = "A" | "B" | "C" | "D"

export function bandOf(item: AttentionQueueItem, now: ISO8601): PriorityBand {
  if (item.actionClass === "ESCALATE" && item.escalationKind === "APPROVAL") return "A"
  const score = scoreItem(item, now)
  if (score >= BAND_B_MIN_SCORE) return "B"
  if (score >= BAND_C_MIN_SCORE) return "C"
  return "D"
}

const surfacedCount = (item: AttentionQueueItem): number => item.lifecycle.filter((event) => event.state === "surfaced").length

const surfacesInLastHour = (root: string, surfaceLog: readonly SurfaceRecord[], now: ISO8601): number =>
  surfaceLog.filter((record) => record.root === root && Date.parse(record.at) > Date.parse(now) - HOUR_MS).length

const consecutiveSurfaces = (root: string, surfaceLog: readonly SurfaceRecord[]): number => {
  let count = 0
  for (let index = surfaceLog.length - 1; index >= 0; index -= 1) {
    if (surfaceLog[index]?.root !== root) break
    count += 1
  }
  return count
}

const hasActiveLease = (item: AttentionQueueItem, lease: PresentationLease | undefined, now: ISO8601): boolean =>
  lease !== undefined && lease.itemID === item.id && Date.parse(lease.expiresAt) > Date.parse(now)

function isEligible(item: AttentionQueueItem, lease: PresentationLease | undefined, now: ISO8601): boolean {
  const state = itemState(item)
  if (state === "resolved" || state === "answered") return false
  if (item.priority.notBefore !== undefined && Date.parse(item.priority.notBefore) > Date.parse(now)) return false
  if (state === "surfaced") return !hasActiveLease(item, lease, now)
  return state === "revalidated" && lastRevalidation(item) === "valid"
}

const compareItems = (left: AttentionQueueItem, right: AttentionQueueItem): number => {
  const surfacedDiff = surfacedCount(left) - surfacedCount(right)
  if (surfacedDiff !== 0) return surfacedDiff
  const createdDiff = Date.parse(left.priority.createdAt) - Date.parse(right.priority.createdAt)
  if (createdDiff !== 0) return createdDiff
  return left.id.localeCompare(right.id)
}

function chooseWithinBand(candidates: readonly AttentionQueueItem[], surfaceLog: readonly SurfaceRecord[], now: ISO8601): AttentionQueueItem | undefined {
  const roots = [...new Set(candidates.map((item) => item.target.root))]
  const fairRoots = roots.filter((root) => consecutiveSurfaces(root, surfaceLog) < MAX_CONSECUTIVE_ROOT_SURFACES)
  const pool = fairRoots.length > 0 ? candidates.filter((item) => fairRoots.includes(item.target.root)) : candidates
  const deficit = new Map<string, number>()
  for (const root of new Set(pool.map((item) => item.target.root))) deficit.set(root, surfacesInLastHour(root, surfaceLog, now))
  const minDeficit = Math.min(...deficit.values())
  const fairest = pool.filter((item) => deficit.get(item.target.root) === minDeficit)
  return [...fairest].sort(compareItems)[0]
}

export type SelectionContext = {
  readonly items: readonly AttentionQueueItem[]
  readonly lease: PresentationLease | undefined
  readonly surfaceLog: readonly SurfaceRecord[]
  readonly now: ISO8601
}

/** Band A (approvals) preempts everything not yet surfaced; then B/C/D with deficit round-robin. */
export function selectNext(context: SelectionContext): AttentionQueueItem | undefined {
  const eligible = context.items.filter((item) => isEligible(item, context.lease, context.now))
  for (const band of ["A", "B", "C", "D"] as const) {
    const candidates = eligible.filter((item) => bandOf(item, context.now) === band)
    if (candidates.length === 0) continue
    const chosen = chooseWithinBand(candidates, context.surfaceLog, context.now)
    if (chosen !== undefined) return chosen
  }
  return undefined
}

export type RevalidationSources = {
  readonly targetExists: (target: TargetRef) => boolean
  readonly targetIdle: (target: TargetRef) => boolean
  readonly latestMessageID: (target: TargetRef) => string | undefined
  readonly targetTurnAborted: (target: TargetRef) => boolean
  readonly ticketOpen: (item: AttentionQueueItem) => boolean
  readonly blackboardFactActive: (premise: Extract<Premise, { kind: "blackboard-fact" }>) => boolean
  readonly canonicalItemFor: (decisionKey: DecisionKey) => QueueItemID | undefined
  readonly answeredElsewhere: (item: AttentionQueueItem) => EvidenceRef | undefined
  readonly approvalRequired: (item: AttentionQueueItem) => boolean
  readonly modePermits: (item: AttentionQueueItem) => boolean
  readonly citationsAdmissible: (item: AttentionQueueItem) => boolean
}

export type RevalidationConfig = {
  readonly now: ISO8601
  readonly graceMs: number
  readonly ttlMs: number
}

export type RevalidationOutcome =
  | { readonly kind: "valid"; readonly evidence: readonly EvidenceRef[] }
  | { readonly kind: "temporarily-invalid"; readonly reason: string; readonly notBefore: ISO8601 }
  | { readonly kind: "materially-changed"; readonly reason: string }
  | { readonly kind: "retired-by-evidence"; readonly reason: string; readonly evidence: readonly EvidenceRef[] }
  | { readonly kind: "superseded"; readonly reason: string }
  | { readonly kind: "expired"; readonly reason: string }
  | { readonly kind: "re-decide"; readonly reason: string }
  | { readonly kind: "downgrade-console-only"; readonly reason: string }

/** §4 check matrix, evaluated in table order; first decisive failure wins. */
export function revalidate(item: AttentionQueueItem, sources: RevalidationSources, config: RevalidationConfig): RevalidationOutcome {
  const { target } = item
  if (!sources.targetExists(target)) return { kind: "superseded", reason: "target session no longer exists" }
  if (!sources.targetIdle(target)) {
    return { kind: "temporarily-invalid", reason: "target is not idle", notBefore: new Date(Date.parse(config.now) + config.graceMs).toISOString() }
  }
  const answered = sources.answeredElsewhere(item)
  const noNewerTurn = item.premises.find((premise) => premise.kind === "no-newer-turn")
  const latest = sources.latestMessageID(target)
  if (noNewerTurn !== undefined && noNewerTurn.kind === "no-newer-turn" && latest !== undefined && latest !== noNewerTurn.latestMessageID) {
    return answered === undefined
      ? { kind: "re-decide", reason: "a newer turn changed the decision context" }
      : { kind: "retired-by-evidence", reason: "a newer turn answers the need", evidence: [answered] }
  }
  if (sources.targetTurnAborted(target)) return { kind: "materially-changed", reason: "target turn was aborted (D295 shape)" }
  if (!sources.ticketOpen(item)) return { kind: "retired-by-evidence", reason: "duplicate item already resolved", evidence: [] }
  const staleFact = item.premises.find((premise) => premise.kind === "blackboard-fact" && !sources.blackboardFactActive(premise))
  if (staleFact !== undefined) return { kind: "re-decide", reason: "a load-bearing blackboard fact is stale" }
  const canonical = sources.canonicalItemFor(item.decisionKey)
  if (canonical !== undefined && canonical !== item.id) return { kind: "re-decide", reason: `decision key already canonicalized as ${canonical}` }
  if (answered !== undefined) return { kind: "retired-by-evidence", reason: "answered elsewhere", evidence: [answered] }
  if (sources.approvalRequired(item) && item.escalationKind !== "APPROVAL") {
    return { kind: "re-decide", reason: "destructive action now requires approval" }
  }
  if (!sources.citationsAdmissible(item)) return { kind: "downgrade-console-only", reason: "origin citations are no longer admissible" }
  if (!sources.modePermits(item)) return { kind: "downgrade-console-only", reason: "root write mode does not permit the outcome" }
  if (item.escalationKind !== "APPROVAL" && Date.parse(config.now) - Date.parse(item.priority.createdAt) > config.ttlMs) {
    return { kind: "expired", reason: "item age exceeds class TTL" }
  }
  return { kind: "valid", evidence: [] }
}

export type LedgerAppend = (type: LedgerRecordType, payload: unknown) => Promise<void>

export type ProposeInput = {
  readonly kind: QueueKind
  readonly origin: OriginTick
  readonly target: TargetRef
  readonly actionClass: Action
  readonly escalationKind?: EscalationKind
  readonly question: string
  readonly rationale: string
  readonly priority: QueuePriorityInputs
  readonly premises: readonly Premise[]
  readonly materialChange?: boolean
}

export type ProposeResult =
  | { readonly kind: "created"; readonly item: AttentionQueueItem }
  | { readonly kind: "merged"; readonly item: AttentionQueueItem }
  | { readonly kind: "deduped"; readonly item: AttentionQueueItem }
  | { readonly kind: "blocked"; readonly reason: string }
export type RevalidationResult = {
  readonly redecide?: true
  readonly outcome: RevalidationOutcome
  readonly item: AttentionQueueItem
  readonly poison: "none" | "suspect" | "expired"
}

export type LeaseResult =
  | { readonly kind: "acquired"; readonly lease: PresentationLease }
  | { readonly kind: "denied"; readonly reason: string; readonly heldBy?: QueueItemID }

export type Resolution = {
  readonly disposition: ResolutionDisposition
  readonly evidence: readonly EvidenceRef[]
  readonly now: ISO8601
  readonly reason: string
  readonly replacementItemID?: QueueItemID
}

export type LeaseRequest = {
  readonly channelID: string
  readonly now: ISO8601
  readonly ttlMs?: number
}

const mergeCitations = (left: readonly Citation[], right: readonly Citation[]): readonly Citation[] => {
  const seen = new Set(left.map((citation) => `${citation.session}\u0000${citation.messageID}\u0000${citation.quote}`))
  const merged = [...left]
  for (const citation of right) {
    const key = `${citation.session}\u0000${citation.messageID}\u0000${citation.quote}`
    if (!seen.has(key)) {
      seen.add(key)
      merged.push(citation)
    }
  }
  return merged
}

const mergePremises = (left: readonly Premise[], right: readonly Premise[]): readonly Premise[] => {
  const seen = new Set(left.map((premise) => premise.id))
  const merged = [...left]
  for (const premise of right) {
    if (!seen.has(premise.id)) {
      seen.add(premise.id)
      merged.push(premise)
    }
  }
  return merged
}

const mergeOrigin = (existing: OriginTick, incoming: OriginTick): OriginTick => ({
  ...existing,
  citations: mergeCitations(existing.citations, incoming.citations),
  informationNeeds: [...existing.informationNeeds, ...incoming.informationNeeds.filter((need) => !existing.informationNeeds.some((known) => known.question === need.question && known.scope === need.scope && known.target === need.target))],
})

function createItem(input: ProposeInput, key: DecisionKey): AttentionQueueItem {
  return {
    schemaVersion: QUEUE_SCHEMA_VERSION,
    id: `att_${timeSortableID()}`,
    version: 1,
    decisionKey: key,
    kind: input.kind,
    origin: input.origin,
    target: input.target,
    actionClass: input.actionClass,
    ...(input.escalationKind === undefined ? {} : { escalationKind: input.escalationKind }),
    question: input.question,
    rationale: input.rationale,
    priority: input.priority,
    premises: input.premises,
    relatedItemIDs: [],
    lifecycle: [{ state: "proposed", at: input.priority.createdAt, actor: input.origin.tickID }],
    poisonCount: 0,
  }
}

/** Merge into a proposed/revalidated item: union evidence, keep earliest createdAt, version++. */
function mergeItem(existing: AttentionQueueItem, input: ProposeInput): AttentionQueueItem {
  return {
    ...existing,
    version: existing.version + 1,
    origin: mergeOrigin(existing.origin, input.origin),
    premises: mergePremises(existing.premises, input.premises),
    lifecycle: [...existing.lifecycle, { state: "proposed", at: input.priority.createdAt, actor: `merge:${input.origin.tickID}` }],
  }
}

/** Corroborate a surfaced/answered item without altering the text before the operator. */
function attachEvidence(existing: AttentionQueueItem, input: ProposeInput): AttentionQueueItem {
  return {
    ...existing,
    version: existing.version + 1,
    origin: mergeOrigin(existing.origin, input.origin),
    premises: mergePremises(existing.premises, input.premises),
  }
}

const withoutLease = (snapshot: QueueSnapshot): QueueSnapshot => ({
  schemaVersion: snapshot.schemaVersion,
  items: snapshot.items,
  surfaceLog: snapshot.surfaceLog,
  digest: snapshot.digest,
})

const emptySnapshot = (): QueueSnapshot => ({ schemaVersion: QUEUE_SCHEMA_VERSION, items: [], surfaceLog: [], digest: [] })

async function loadSnapshot(path: string): Promise<QueueSnapshot> {
  try {
    const parsed = JSON.parse(await readFile(path, "utf8")) as QueueSnapshot
    if (parsed.schemaVersion !== QUEUE_SCHEMA_VERSION) throw new Error(`unsupported queue snapshot schema ${parsed.schemaVersion}`)
    return parsed
  } catch (error) {
    if (error instanceof Error && "code" in error && error.code === "ENOENT") return emptySnapshot()
    throw error
  }
}

export class AttentionQueue {
  private snapshot: QueueSnapshot

  private constructor(
    private readonly path: string,
    private readonly append: LedgerAppend,
    snapshot: QueueSnapshot,
    private readonly protectedSession?: (sessionID: string) => boolean,
  ) {
    this.snapshot = snapshot
  }
  static async open(options: { readonly path: string; readonly append: LedgerAppend; readonly now?: ISO8601; readonly protectedSession?: (sessionID: string) => boolean }): Promise<AttentionQueue> {
    const queue = new AttentionQueue(options.path, options.append, await loadSnapshot(options.path), options.protectedSession)
    await queue.recover(options.now ?? new Date().toISOString())
    return queue
  }

  get items(): readonly AttentionQueueItem[] {
    return this.snapshot.items
  }

  get lease(): PresentationLease | undefined {
    return this.snapshot.lease
  }

  get digest(): readonly string[] {
    return this.snapshot.digest
  }

  /** Drop a stale presentation lease on restart; the item returns to eligible with the same ID. */
  private async recover(now: ISO8601): Promise<void> {
    const lease = this.snapshot.lease
    if (lease === undefined || Date.parse(lease.expiresAt) > Date.parse(now)) return
    this.snapshot = withoutLease(this.snapshot)
    await this.append("CHANNEL_DEFERRED", { presentationID: lease.presentationID, itemID: lease.itemID, reason: "lease expired on recovery" })
    await this.persist()
  }

  private find(itemID: QueueItemID): AttentionQueueItem | undefined {
    return this.snapshot.items.find((item) => item.id === itemID)
  }

  private replaceItem(item: AttentionQueueItem): void {
    this.snapshot = { ...this.snapshot, items: this.snapshot.items.map((existing) => (existing.id === item.id ? item : existing)) }
  }

  private activeLease(now: ISO8601): PresentationLease | undefined {
    const lease = this.snapshot.lease
    return lease !== undefined && Date.parse(lease.expiresAt) > Date.parse(now) ? lease : undefined
  }

  private async persist(): Promise<void> {
    await mkdir(dirname(this.path), { recursive: true })
    const temporary = `${this.path}.tmp-${process.pid}-${randomUUID()}`
    const surfaceLog = this.snapshot.surfaceLog.slice(-SURFACE_LOG_CAP)
    await writeFile(temporary, JSON.stringify({ ...this.snapshot, surfaceLog }, null, 2), { mode: 0o600 })
    await rename(temporary, this.path)
  }

  async propose(input: ProposeInput): Promise<ProposeResult> {
    // Protection overlay: protected sessions are never CONTINUE (kick-start) proposals;
    // ESCALATE still proposes — the operator can always be asked.
    if (input.actionClass === "CONTINUE" && this.protectedSession?.(input.target.sessionID) === true) {
      const reason = `session ${input.target.sessionID} is protected by the operator (no auto-continuation)`
      await this.append("QUEUE_PROPOSAL_DEDUPED", { root: input.target.root, sessionID: input.target.sessionID, reason })
      return { kind: "blocked", reason }
    }
    const key = decisionKey({
      root: input.target.root,
      sessionID: input.target.sessionID,
      actionClass: input.actionClass,
      ...(input.escalationKind === undefined ? {} : { escalationKind: input.escalationKind }),
      subject: input.question,
    })
    const match = this.snapshot.items.find((item) => item.decisionKey === key)
    if (match === undefined) {
      const item = createItem(input, key)
      this.snapshot = { ...this.snapshot, items: [...this.snapshot.items, item] }
      await this.append("QUEUE_ITEM_PROPOSED", { itemID: item.id, itemVersion: item.version, decisionKey: key, root: item.target.root })
      await this.persist()
      return { kind: "created", item }
    }
    const state = itemState(match)
    if (state === "resolved") {
      if (input.materialChange !== true) {
        await this.append("QUEUE_PROPOSAL_DEDUPED", { itemID: match.id, decisionKey: key, reason: "terminal match without material change" })
        return { kind: "deduped", item: match }
      }
      const item = createItem(input, key)
      this.snapshot = { ...this.snapshot, items: [...this.snapshot.items, item] }
      await this.append("QUEUE_ITEM_PROPOSED", { itemID: item.id, itemVersion: item.version, decisionKey: key, root: item.target.root, supersedes: match.id })
      await this.persist()
      return { kind: "created", item }
    }
    const merged = state === "surfaced" || state === "answered" ? attachEvidence(match, input) : mergeItem(match, input)
    this.replaceItem(merged)
    await this.append("QUEUE_ITEM_MERGED", { itemID: merged.id, itemVersion: merged.version, decisionKey: key, state })
    await this.persist()
    return { kind: "merged", item: merged }
  }

  async revalidate(itemID: QueueItemID, sources: RevalidationSources, config: RevalidationConfig): Promise<RevalidationResult> {
    const item = this.find(itemID)
    if (item === undefined) throw new Error(`unknown queue item ${itemID}`)
    const outcome = revalidate(item, sources, config)
    if (outcome.kind === "re-decide") {
      const redecideCount = (item.redecideCount ?? 0) + 1
      const next = this.commit({ ...item, redecideCount }, { state: "revalidated", at: config.now, result: "materially-changed", evidence: [] }, item.poisonCount)
      await this.append("QUEUE_ITEM_REVALIDATED", { itemID, itemVersion: next.version, result: "materially-changed", policy: outcome.kind, redecideCount })
      if (redecideCount % REDECIDE_HIGH_WATER === 0) {
        const message = `queue item ${itemID} remains open after ${redecideCount} re-decisions: ${outcome.reason}`
        await this.recordDigestDiagnostic(message)
        await this.append("QUEUE_REDECIDE_DIAGNOSTIC", { itemID, root: item.target.root, redecideCount, message })
      }
      await this.persist()
      return { outcome, item: next, poison: "none", redecide: true }
    }
    if (outcome.kind === "valid") {
      const next = this.commit(item, { state: "revalidated", at: config.now, result: "valid", evidence: outcome.evidence }, 0)
      await this.append("QUEUE_ITEM_REVALIDATED", { itemID, itemVersion: next.version, result: "valid" })
      await this.persist()
      return { outcome, item: next, poison: "none" }
    }
    if (outcome.kind === "temporarily-invalid") {
      const withNotBefore = { ...item, priority: { ...item.priority, notBefore: outcome.notBefore } }
      const next = this.commit(withNotBefore, { state: "revalidated", at: config.now, result: "temporarily-invalid", evidence: [] }, item.poisonCount)
      await this.append("QUEUE_ITEM_REVALIDATED", { itemID, itemVersion: next.version, result: "temporarily-invalid", notBefore: outcome.notBefore })
      await this.persist()
      return { outcome, item: next, poison: "none" }
    }
    const poisonCount = item.poisonCount + 1
    if (poisonCount >= POISON_EXPIRE_THRESHOLD) {
      const resolved = await this.resolveInternal({ ...item, poisonCount }, { disposition: "expired", evidence: [], now: config.now, reason: `poison: ${outcome.reason}` })
      await this.recordDigestDiagnostic(`queue item ${item.id} expired after repeated revalidation failures: ${outcome.reason}`)
      return { outcome: { kind: "expired", reason: outcome.reason }, item: resolved, poison: "expired" }
    }
    const effective: RevalidationOutcome = poisonCount >= POISON_SUSPECT_THRESHOLD ? { kind: "re-decide", reason: `poison-suspect: ${outcome.reason}` } : outcome
    if (effective.kind === "retired-by-evidence" || effective.kind === "superseded" || effective.kind === "materially-changed" || effective.kind === "expired") {
      const disposition: ResolutionDisposition = effective.kind === "retired-by-evidence" ? "retired-by-evidence" : effective.kind === "expired" ? "expired" : "superseded"
      const evidence = effective.kind === "retired-by-evidence" ? effective.evidence : []
      const resolved = await this.resolveInternal({ ...item, poisonCount }, { disposition, evidence, now: config.now, reason: effective.reason })
      return { outcome: effective, item: resolved, poison: "none" }
    }
    const next = this.commit({ ...item, poisonCount }, { state: "revalidated", at: config.now, result: "materially-changed", evidence: [] }, poisonCount)
    await this.append("QUEUE_ITEM_REVALIDATED", { itemID, itemVersion: next.version, result: "materially-changed", policy: effective.kind, poisonCount })
    await this.persist()
    return { outcome: effective, item: next, poison: poisonCount >= POISON_SUSPECT_THRESHOLD ? "suspect" : "none", ...(effective.kind === "re-decide" ? { redecide: true } : {}) }
  }

  private commit(item: AttentionQueueItem, event: LifecycleEvent, poisonCount: number): AttentionQueueItem {
    const next = { ...item, version: item.version + 1, poisonCount, lifecycle: [...item.lifecycle, event] }
    this.replaceItem(next)
    return next
  }

  private async resolveInternal(item: AttentionQueueItem, resolution: Resolution): Promise<AttentionQueueItem> {
    // Terminal-state guard: a resolved item is immutable. Re-resolving would append a
    // duplicate QUEUE_ITEM_RESOLVED row and bump the version for no state change
    // (2026-10-09 audit: 18 items resolved repeatedly → 132 excess rows).
    if (itemState(item) === "resolved") return item
    const event: LifecycleEvent = { state: "resolved", at: resolution.now, disposition: resolution.disposition, evidence: resolution.evidence, ...(resolution.replacementItemID === undefined ? {} : { replacementItemID: resolution.replacementItemID }) }
    const next = this.commit(item, event, item.poisonCount)
    await this.append("QUEUE_ITEM_RESOLVED", { itemID: item.id, itemVersion: next.version, disposition: resolution.disposition, reason: resolution.reason, evidence: resolution.evidence })
    await this.persist()
    return next
  }

  async resolve(itemID: QueueItemID, resolution: Resolution): Promise<AttentionQueueItem> {
    const item = this.find(itemID)
    if (item === undefined) throw new Error(`unknown queue item ${itemID}`)
    return this.resolveInternal(item, resolution)
  }

  selectNext(now: ISO8601): AttentionQueueItem | undefined {
    return selectNext({ items: this.snapshot.items, lease: this.activeLease(now), surfaceLog: this.snapshot.surfaceLog, now })
  }

  /** Single global presentation lease for DEMANDING channels (spec §7.2). */
  async acquireLease(itemID: QueueItemID, request: LeaseRequest): Promise<LeaseResult> {
    const item = this.find(itemID)
    if (item === undefined) throw new Error(`unknown queue item ${itemID}`)
    const state = itemState(item)
    if (state === "resolved" || state === "answered") return { kind: "denied", reason: `item is ${state}` }
    if (item.priority.notBefore !== undefined && Date.parse(item.priority.notBefore) > Date.parse(request.now)) return { kind: "denied", reason: "item is snoozed" }
    const active = this.activeLease(request.now)
    if (active !== undefined) return { kind: "denied", reason: "global presentation lease held", heldBy: active.itemID }
    const presentationID = `pres_${timeSortableID()}`
    const ttlMs = request.ttlMs ?? LEASE_TTL_MS
    const lease: PresentationLease = { presentationID, itemID, channelID: request.channelID, acquiredAt: request.now, heartbeatAt: request.now, expiresAt: new Date(Date.parse(request.now) + ttlMs).toISOString() }
    // Keep the existing lifecycle state for lease recovery; delivery is confirmed separately.
    const next = this.commit(item, { state: "surfaced", at: request.now, channelID: request.channelID, presentationID }, item.poisonCount)
    this.snapshot = { ...this.snapshot, lease }
    await this.append("QUEUE_ITEM_LEASED", { itemID, itemVersion: next.version, channelID: request.channelID, presentationID })
    await this.persist()
    return { kind: "acquired", lease }
  }

  async confirmSurfaced(itemID: QueueItemID, presentationID: string, now: ISO8601): Promise<void> {
    const item = this.find(itemID)
    if (item === undefined) throw new Error(`unknown queue item ${itemID}`)
    const lease = this.snapshot.lease
    if (lease === undefined || lease.itemID !== itemID || lease.presentationID !== presentationID || lease.confirmedAt !== undefined) return
    this.snapshot = { ...this.snapshot, lease: { ...lease, confirmedAt: now }, surfaceLog: [...this.snapshot.surfaceLog, { root: item.target.root, itemID, at: now }] }
    await this.append("QUEUE_ITEM_SURFACED", { itemID, itemVersion: item.version, channelID: lease.channelID, presentationID })
    await this.persist()
  }

  /** Deferral is a scheduling request, never a retire: release the lease, set notBefore, keep aging. */
  async defer(presentationID: string, notBefore: ISO8601, now: ISO8601): Promise<void> {
    const lease = this.snapshot.lease
    if (lease === undefined || lease.presentationID !== presentationID) return
    const item = this.find(lease.itemID)
    if (item !== undefined) this.replaceItem({ ...item, priority: { ...item.priority, notBefore } })
    this.snapshot = withoutLease(this.snapshot)
    await this.append("CHANNEL_DEFERRED", { presentationID, itemID: lease.itemID, channelID: lease.channelID, notBefore, at: now })
    await this.persist()
  }

  async expireLeases(now: ISO8601): Promise<readonly QueueItemID[]> {
    const lease = this.snapshot.lease
    if (lease === undefined || Date.parse(lease.expiresAt) > Date.parse(now)) return []
    this.snapshot = withoutLease(this.snapshot)
    await this.persist()
    return [lease.itemID]
  }

  async markAnswered(itemID: QueueItemID, replyEventID: string, channelID: string, now: ISO8601): Promise<AttentionQueueItem> {
    const item = this.find(itemID)
    if (item === undefined) throw new Error(`unknown queue item ${itemID}`)
    // Idempotency guard: an already-answered item is a no-op — no lifecycle row, no
    // version bump, no persist (panel directive D1.2).
    if (itemState(item) === "answered") return item
    const next = this.commit(item, { state: "answered", at: now, replyEventID, channelID }, item.poisonCount)
    await this.append("QUEUE_REPLY_RECEIVED", { itemID, itemVersion: next.version, replyEventID, channelID })
    await this.persist()
    return next
  }

  /** Poison diagnostic lands in the digest, never as another live ticket (spec §4). */
  async recordDigestDiagnostic(message: string): Promise<void> {
    this.snapshot = { ...this.snapshot, digest: [...this.snapshot.digest, message] }
    await this.persist()
  }
}

/** Open (non-resolved) attention items per root — the only correct source for
 *  `status.queueDepths`. Replaces the hand-incremented counter that drifted
 *  from the operator-view read model (2026-09-30 audit: 0 vs 4 open cards). */
export function openItemsByRoot(items: readonly AttentionQueueItem[]): Readonly<Record<string, number>> {
  const depths: Record<string, number> = {}
  for (const item of items) {
    if (itemState(item) === "resolved") continue
    depths[item.target.root] = (depths[item.target.root] ?? 0) + 1
  }
  return depths
}
