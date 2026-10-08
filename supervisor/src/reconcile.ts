import type { OpencodeClient } from "./client"
import { projectTurns } from "./projector"
import { deriveChildSessionIDs, topLevelSessions } from "./topology"
import type { Message, OriginRegistry, Session, Turn } from "./types"

export type SessionScan = {
  readonly session: Session
  readonly messages: readonly Message[]
  readonly turns: readonly Turn[]
  readonly watermark?: string
}

export type ScanManifest = {
  readonly root: string
  readonly startedAt: string
  readonly completedAt: string
  readonly complete: true
  /** Sessions whose transcript fetch failed and are absent from `sessions` (degraded, not fatal). */
  readonly fetchErrors: readonly { readonly sessionID: string; readonly error: string }[]
  /** Sessions that entered fetch backoff during this scan (fires once per entry). */
  readonly backoffEntered?: readonly string[]
  /** Backoffed sessions whose fetch succeeded again during this scan (fires once per recovery). */
  readonly backoffRecovered?: readonly string[]
  readonly childSessionIDs: readonly string[]
  readonly sessions: readonly SessionScan[]
  /** sessionID → timeUpdatedMs observed this scan; drives skip-unchanged fetches. */
  readonly sessionMarks: Readonly<Record<string, number>>
}

export type ReconcileOptions = {
  readonly initialWindowDays: number
  readonly fetchConcurrency: number
  readonly nowMs?: () => number
  readonly sessionBackoff?: SessionBackoff
  /** Shutdown signal: aborts in-flight fetches so stop does not wait out a sweep. */
  readonly signal?: AbortSignal
  /** Previous manifest of this root; unchanged sessions reuse their scan (no fetch). */
  readonly previous?: ScanManifest | undefined
}

const DAY_MS = 86_400_000

const BACKOFF_THRESHOLD = 3
const BACKOFF_CAP_MS = 1_800_000

type BackoffState = { failures: number; blockedUntilMs: number; enteredReported: boolean }

/**
 * Per-session fetch backoff: a session failing BACKOFF_THRESHOLD consecutive
 * reconciles is skipped from fetching for an escalating delay (60s first,
 * then 2^min(failures-3,5)×60s, capped at 30m — mirrors the root backoff
 * formula in service.ts).
 */
export class SessionBackoff {
  private readonly states = new Map<string, BackoffState>()

  /** Records a failed fetch; returns true exactly once per entry into backoff. */
  recordFailure(sessionID: string, nowMs: number): boolean {
    const previous = this.states.get(sessionID) ?? { failures: 0, blockedUntilMs: 0, enteredReported: false }
    const failures = previous.failures + 1
    const blockedUntilMs = failures < BACKOFF_THRESHOLD
      ? 0
      : nowMs + Math.min(2 ** Math.min(failures - BACKOFF_THRESHOLD, 5) * 60_000, BACKOFF_CAP_MS)
    const entered = blockedUntilMs > 0 && !previous.enteredReported
    this.states.set(sessionID, { failures, blockedUntilMs, enteredReported: previous.enteredReported || entered })
    return entered
  }

  /** Records a successful fetch; returns true when a backoffed session recovers. */
  recordSuccess(sessionID: string): boolean {
    const state = this.states.get(sessionID)
    this.states.delete(sessionID)
    return state !== undefined && state.failures >= BACKOFF_THRESHOLD
  }

  isBlocked(sessionID: string, nowMs: number): boolean {
    const state = this.states.get(sessionID)
    return state !== undefined && nowMs < state.blockedUntilMs
  }

  blockedUntil(sessionID: string): number | undefined {
    return this.states.get(sessionID)?.blockedUntilMs
  }
}

async function mapPool<T, R>(items: readonly T[], limit: number, operation: (item: T) => Promise<R>): Promise<readonly R[]> {
  const results = new Array<R>(items.length)
  const entries = items.entries()
  const workers = Array.from({ length: Math.min(limit, items.length) }, async () => {
    for (const [index, item] of entries) results[index] = await operation(item)
  })
  await Promise.all(workers)
  return results
}

export function changedTurnsSinceWatermark(
  previousWatermark: string | undefined,
  scan: SessionScan,
): readonly Turn[] {
  if (previousWatermark === undefined) return scan.turns
  const watermarkIndex = scan.messages.findIndex((message) => message.id === previousWatermark)
  if (watermarkIndex < 0) return scan.turns
  const changedIDs = new Set(scan.messages.slice(watermarkIndex + 1).map((message) => message.id))
  return scan.turns.filter((turn) => changedIDs.has(turn.userMessageID) ||
    (turn.assistantMessageID !== undefined && changedIDs.has(turn.assistantMessageID)))
}

/**
 * Full authoritative scan of one root. SSE is only a hint; this is the truth.
 * - Lists sessions (page limit 2000) and keeps those updated within the window
 *   (session timestamps are epoch milliseconds — verified live).
 * - Fetches messages for every in-window session with bounded concurrency.
 * - Derives child session IDs from task-tool parts, THEN selects top-level sessions.
 * - Writes are armed only after this manifest completes (see service).
 */
export async function reconcileRoot(
  client: OpencodeClient,
  root: string,
  registry: OriginRegistry,
  options: ReconcileOptions,
  excludeIDs: ReadonlySet<string> = new Set(),
): Promise<ScanManifest> {
  const startedAt = new Date().toISOString()
  const nowMs = options.nowMs?.() ?? Date.now()
  const cutoff = nowMs - options.initialWindowDays * DAY_MS
  const all = await client.listSessions(root)
  const inWindow = all.filter(
    (session) => !excludeIDs.has(session.id) && (session.timeUpdatedMs === undefined || session.timeUpdatedMs >= cutoff),
  )
  const fetchErrors: { readonly sessionID: string; readonly error: string }[] = []
  const backoffEntered: string[] = []
  const backoffRecovered: string[] = []
  const previousMarks = options.previous?.sessionMarks ?? {}
  const previousScans = new Map((options.previous?.sessions ?? []).map((scan) => [scan.session.id, scan]))
  // Skip-unchanged diet (2026-10-07 thrash root cause): a full sweep used to fetch
  // messages for EVERY in-window session (~2.2k/7d) even when nothing changed —
  // hydrating up to 50 messages x 2.2k sessions through the server on every sweep
  // and on every idle tick. Reuse the previous scan when timeUpdatedMs is unchanged.
  const marks: Record<string, number> = {}
  const reused: SessionScan[] = []
  const toFetch: Session[] = []
  for (const session of inWindow) {
    const mark = session.timeUpdatedMs
    const previousScan = previousScans.get(session.id)
    if (mark !== undefined && previousMarks[session.id] === mark) {
      marks[session.id] = mark
      if (previousScan !== undefined) reused.push(previousScan)
    } else {
      toFetch.push(session)
    }
  }
  // Blocked sessions are skipped from FETCHING only — `inWindow` stays intact so
  // topology (topLevelSessions) still sees them and their children do not get
  // promoted to top-level while the parent is in backoff.
  const sessionBackoff = options.sessionBackoff
  const fetchPool = sessionBackoff === undefined
    ? toFetch
    : toFetch.filter((session) => !sessionBackoff.isBlocked(session.id, nowMs))
  const aborted = (): boolean => options.signal?.aborted === true
  const fetched = await mapPool(fetchPool, options.fetchConcurrency, async (session): Promise<SessionScan | undefined> => {
    if (aborted()) return undefined
    if (options.signal?.aborted === true) return undefined
    // Per-session isolation: one failing transcript fetch (after client retries)
    // must degrade that session only — never kill the whole service (live crash
    // 2026-09-30 18:12: single /session/<id>/message failure exited the process).
    try {
      const messages = await client.listMessages(session.id, root, 50, options.signal)
      if (session.timeUpdatedMs !== undefined) marks[session.id] = session.timeUpdatedMs
      if (options.sessionBackoff?.recordSuccess(session.id)) backoffRecovered.push(session.id)
      const watermark = messages.at(-1)?.id
      return {
        session,
        messages,
        turns: [],
        ...(watermark === undefined ? {} : { watermark }),
      }
    } catch (error) {
      if (aborted()) throw error
      if (options.sessionBackoff?.recordFailure(session.id, nowMs)) backoffEntered.push(session.id)
      fetchErrors.push({ sessionID: session.id, error: error instanceof Error ? error.message : String(error) })
      return undefined
    }
  })
  const scans = fetched.filter((scan): scan is SessionScan => scan !== undefined)
  const childIDs = new Set([...(options.previous?.childSessionIDs ?? []), ...deriveChildSessionIDs(scans.flatMap((scan) => scan.messages))])
  const top = new Set(topLevelSessions(inWindow, childIDs).map((session) => session.id))
  const sessions = [
    ...reused.filter((scan) => top.has(scan.session.id)),
    ...scans.filter((scan) => top.has(scan.session.id)).map((scan) => ({ ...scan, turns: projectTurns(scan.messages, registry) })),
  ]
  return { root, startedAt, completedAt: new Date().toISOString(), complete: true, fetchErrors, backoffEntered, backoffRecovered, childSessionIDs: [...childIDs], sessions, sessionMarks: marks }
}
