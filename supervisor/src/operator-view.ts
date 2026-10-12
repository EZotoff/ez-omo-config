// Atomic operator-view.json publication (orca-transition plan Task 2; contract
// amendment per docs/portable-supervisor-contract.md). The Supervisor stays
// read-only on the ledger: this module only ever WRITES operator-view.json.
import { randomUUID } from "node:crypto"
import { mkdir, open, readFile, rename } from "node:fs/promises"
import { tmpdir } from "node:os"
import { dirname } from "node:path"
import { bandOf, itemState } from "./queue"
import { truncateAtSentence } from "./text"
import type { AttentionQueueItem, DecisionSummary, ISO8601, Premise } from "./types"

export const OPERATOR_VIEW_SCHEMA_VERSION = 1
/** Contract heartbeat obligation: republish at most every 15 s even when idle. */
export const OPERATOR_VIEW_HEARTBEAT_MS = 15_000

// Bounded read-model caps (design §5: bounded active queue cards + capped text).
export const MAX_CARDS = 20
export const MAX_TEXT_CHARS = 4000
export const MAX_PREMISES = 5
export const MAX_PREMISE_CHARS = 1600

export type OperatorViewCard = {
  readonly id: string
  readonly rootLabel: string
  readonly sessionLabel: string
  readonly reasonText: string
  readonly premiseTexts: readonly string[]
  readonly ageSeconds: number
  readonly severity: "A" | "B" | "C" | "D"
  /** Hosting is resolved renderer-side; the publisher always offers the jump. */
  readonly jumpAvailable: true
  /** Queue Action vocabulary (e.g. ESCALATE); the publisher always sets it, pre-amendment images may lack it. */
  readonly actionClass?: string | undefined
  /** Absolute project root path (reply targeting); the publisher always sets it, pre-amendment images may lack it. */
  readonly root?: string | undefined
  readonly escalationKind?: "DECISION" | "INFORMATION" | "APPROVAL" | undefined
  /** Operator-register summary (Amendment 2026-10-11); budgets enforced upstream at decision parse. */
  readonly headline?: string | undefined
  readonly ask?: string | undefined
  readonly options?: readonly string[] | undefined
  readonly recommendation?: string | undefined
}

export type OperatorView = {
  readonly schemaVersion: typeof OPERATOR_VIEW_SCHEMA_VERSION
  readonly generation: number
  readonly lastSeq: number
  readonly producedAt: ISO8601
  readonly cards: readonly OperatorViewCard[]
}

/**
 * Probe/throwaway classification (the omo-focus "PROBE-OK" lesson, design §4/§5):
 * title patterns mirror scripts/sweep-throwaway-sessions.py GLOBAL_TITLE_PATTERNS,
 * plus any session whose root lives under the system tmpdir (scratch-instance rule).
 * Applied BEFORE card computation so a probe burst neither adds nor displaces cards.
 */
const PROBE_TITLE_PATTERNS: readonly RegExp[] = [
  /^(?:GLM-SJ-|GLM-JUDGE-|OPENAI-|K3-)?PROBE-OK(?: probe| reply test)?$/i,
  /^LB_OK/,
  /^[Pp]robe [Oo][Kk]$/,
  /^(?:Model probe test|GLM-5\.3 probe (?:reply )?test(?: message)?|Probe request handling|OAuth probe request|Probe echo test|Probe message title|Probe reply test)$/,
  /^(?:Reply to ALL_GREEN status message|Reply FINAL_OK confirmation|Exact-reply prompt test)$/,
]

export function isProbeTarget(input: { readonly root: string; readonly sessionTitle?: string }): boolean {
  if (input.root.startsWith(`${tmpdir()}/`) || input.root === tmpdir()) return true
  return input.sessionTitle !== undefined && PROBE_TITLE_PATTERNS.some((pattern) => pattern.test(input.sessionTitle ?? ""))
}

export const isProbeItem = (item: AttentionQueueItem): boolean =>
  isProbeTarget({ root: item.target.root, ...(item.target.sessionTitle === undefined ? {} : { sessionTitle: item.target.sessionTitle }) })

const premiseSummary = (premise: Premise): string => {
  switch (premise.kind) {
    case "session-idle":
      return `session-idle: ${premise.sessionID}`
    case "no-newer-turn":
      return `no-newer-turn: ${premise.sessionID} @ ${premise.latestMessageID}`
    case "ticket-open":
      return `ticket-open: ${premise.ticketID} v${premise.observedVersion}`
    case "blackboard-fact":
      return `blackboard-fact: ${premise.factID} v${premise.factVersion}`
    case "sibling-decision":
      return `sibling-decision: ${premise.tickID} (ledger ${premise.ledgerSeq})`
    case "operator-approval-required":
      return `approval-required: ${premise.rationale}`
  }
}

const BAND_ORDER = { A: 0, B: 1, C: 2, D: 3 } as const

const rootLabelOf = (root: string): string => root.split("/").filter((segment) => segment.length > 0).at(-1) ?? root

/** toCard reads `summary` additively (queue.ts todo); typed structurally so this module compiles before/after queue.ts lands it. */
type CardSourceItem = AttentionQueueItem & { readonly summary?: DecisionSummary }

function toCard(item: CardSourceItem, nowMs: number): OperatorViewCard {
  return {
    id: item.id,
    rootLabel: rootLabelOf(item.target.root),
    sessionLabel: item.target.sessionTitle ?? item.target.sessionID,
    // Sentence-boundary trim: a hard slice cut cards mid-sentence on OC Beacon
    // (operator-view is the binding live-card source — audit 2026-10-01).
    reasonText: truncateAtSentence(item.question, MAX_TEXT_CHARS),
    premiseTexts: item.premises.slice(0, MAX_PREMISES).map((premise) => truncateAtSentence(premiseSummary(premise), MAX_PREMISE_CHARS)),
    ageSeconds: Math.max(0, Math.floor((nowMs - Date.parse(item.priority.createdAt)) / 1000)),
    severity: bandOf(item, new Date(nowMs).toISOString()),
    jumpAvailable: true,
    actionClass: item.actionClass,
    root: item.target.root,
    ...(item.escalationKind === undefined ? {} : { escalationKind: item.escalationKind }),
    ...(item.summary === undefined
      ? {}
      : {
          headline: item.summary.headline,
          ask: item.summary.ask,
          ...(item.summary.options === undefined ? {} : { options: item.summary.options }),
          ...(item.summary.recommendation === undefined ? {} : { recommendation: item.summary.recommendation }),
        }),
  }
}

export type BuildOperatorViewInput = {
  readonly items: readonly AttentionQueueItem[]
  /** ledger length (last seq) as observed at the same instant as `items`. */
  readonly ledgerSeq: number
  readonly generation: number
  readonly nowMs: number
  /** Monotonic floor: a seq incorporated by an earlier publish is never retracted. */
  readonly previousLastSeq?: number
  readonly isProbe?: (item: AttentionQueueItem) => boolean
}

export type BuiltOperatorView = {
  readonly view: OperatorView
  /** Seq floor to carry into the next publish for monotonicity. */
  readonly lastSeq: number
}

/**
 * Pure derivation: probe filter FIRST, then active filter, band ordering, caps.
 * `lastSeq` never exceeds the ledger prefix incorporated into the published
 * cards (max origin.ledgerSeq across cards, clamped to the observed ledgerSeq;
 * the previous floor only retains a seq this publisher already published).
 */
export function buildOperatorView(input: BuildOperatorViewInput): BuiltOperatorView {
  const probe = input.isProbe ?? isProbeItem
  const active = input.items
    .filter((item) => probe(item) === false)
    .filter((item) => {
      const state = itemState(item)
      return state !== "resolved" && state !== "answered"
    })
  const ordered = [...active].sort((left, right) => {
    const now = new Date(input.nowMs).toISOString()
    const bandDiff = BAND_ORDER[bandOf(left, now)] - BAND_ORDER[bandOf(right, now)]
    if (bandDiff !== 0) return bandDiff
    const createdDiff = Date.parse(left.priority.createdAt) - Date.parse(right.priority.createdAt)
    if (createdDiff !== 0) return createdDiff
    return left.id.localeCompare(right.id)
  })
  const cards = ordered.slice(0, MAX_CARDS).map((item) => toCard(item, input.nowMs))
  const maxCardSeq = ordered
    .slice(0, MAX_CARDS)
    .reduce((max, item) => Math.max(max, item.origin.ledgerSeq), 0)
  const lastSeq = Math.max(input.previousLastSeq ?? 0, Math.min(maxCardSeq, input.ledgerSeq))
  return {
    view: {
      schemaVersion: OPERATOR_VIEW_SCHEMA_VERSION,
      generation: input.generation,
      lastSeq,
      producedAt: new Date(input.nowMs).toISOString(),
      cards,
    },
    lastSeq,
  }
}

/** Temp name deliberately does NOT match `operator-view.json` so no auto-discovery glob ever sees a partial image. */
async function atomicWrite(path: string, content: string): Promise<void> {
  await mkdir(dirname(path), { recursive: true })
  const temporary = `${path}.tmp-${process.pid}-${randomUUID()}`
  const handle = await open(temporary, "w", 0o600)
  try {
    await handle.writeFile(content)
    await handle.sync()
  } finally {
    await handle.close()
  }
  await rename(temporary, path)
}


/** Persisted generation floor: `{"generation": N}`. Absent/corrupt → 0 (the caller's
 *  epoch-minute seed still guarantees a monotonic jump above any legacy counter). */
async function readGenerationFloor(path: string): Promise<number> {
  try {
    const parsed: unknown = JSON.parse(await readFile(path, "utf8"))
    const value = (parsed as { generation?: unknown }).generation
    return typeof value === "number" && Number.isFinite(value) && value >= 0 ? value : 0
  } catch {
    return 0
  }
}

export type OperatorViewPublisherOptions = {
  readonly path: string
  readonly items: () => readonly AttentionQueueItem[]
  readonly ledgerSeq: () => number
  readonly nowMs?: () => number
  readonly isProbe?: (item: AttentionQueueItem) => boolean
  /** Heartbeat failures land here instead of becoming unhandled rejections. */
  readonly onHeartbeatError?: (error: unknown) => void
  /** Persisted generation floor (restart monotonicity, 2026-10-12): when set, generation resumes above the last published value instead of resetting to 0 — a reset regresses readers (OC Beacon GENERATION_REGRESSION freeze). First boot seeds from epoch minutes, far above any legacy process-lifetime counter. */
  readonly generationFloorPath?: string
}

export class OperatorViewPublisher {
  private generation = 0
  private lastSeq = 0
  private generationFloorLoaded = false
  private heartbeat?: ReturnType<typeof setInterval> | undefined
  private readonly nowMs: () => number

  constructor(private readonly options: OperatorViewPublisherOptions) {
    this.nowMs = options.nowMs ?? Date.now
  }

  async publish(): Promise<OperatorView> {
    if (this.options.generationFloorPath !== undefined && !this.generationFloorLoaded) {
      const persisted = await readGenerationFloor(this.options.generationFloorPath)
      this.generation = Math.max(persisted, Math.floor(Date.now() / 60_000))
      this.generationFloorLoaded = true
    }
    this.generation += 1
    const built = buildOperatorView({
      items: this.options.items(),
      ledgerSeq: this.options.ledgerSeq(),
      generation: this.generation,
      nowMs: this.nowMs(),
      previousLastSeq: this.lastSeq,
      ...(this.options.isProbe === undefined ? {} : { isProbe: this.options.isProbe }),
    })
    this.lastSeq = built.lastSeq
    await atomicWrite(this.options.path, `${JSON.stringify(built.view, null, 2)}\n`)
    if (this.options.generationFloorPath !== undefined) {
      await atomicWrite(this.options.generationFloorPath, `${JSON.stringify({ generation: this.generation })}\n`)
    }
    return built.view
  }

  startHeartbeat(intervalMs: number = OPERATOR_VIEW_HEARTBEAT_MS): void {
    this.stop()
    this.heartbeat = setInterval(() => {
      this.publish().catch((error: unknown) => this.options.onHeartbeatError?.(error))
    }, intervalMs)
  }

  stop(): void {
    if (this.heartbeat !== undefined) {
      clearInterval(this.heartbeat)
      this.heartbeat = undefined
    }
  }
}
