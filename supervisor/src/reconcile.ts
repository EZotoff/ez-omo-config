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
  readonly childSessionIDs: readonly string[]
  readonly sessions: readonly SessionScan[]
}

export type ReconcileOptions = {
  readonly initialWindowDays: number
  readonly fetchConcurrency: number
  readonly nowMs?: () => number
}

const DAY_MS = 86_400_000

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
  const fetched = await mapPool(inWindow, options.fetchConcurrency, async (session): Promise<SessionScan> => {
    const messages = await client.listMessages(session.id, root)
    const watermark = messages.at(-1)?.id
    return {
      session,
      messages,
      turns: [],
      ...(watermark === undefined ? {} : { watermark }),
    }
  })
  const childIDs = deriveChildSessionIDs(fetched.flatMap((scan) => scan.messages))
  const top = new Set(topLevelSessions(inWindow, childIDs).map((session) => session.id))
  const sessions = fetched
    .filter((scan) => top.has(scan.session.id))
    .map((scan) => ({ ...scan, turns: projectTurns(scan.messages, registry) }))
  return { root, startedAt, completedAt: new Date().toISOString(), complete: true, childSessionIDs: [...childIDs], sessions }
}
