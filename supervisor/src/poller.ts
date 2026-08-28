import type { OpencodeClient } from "./client"
import type { Session } from "./types"

export type PollSignal =
  | { readonly kind: "busy"; readonly sessionID: string }
  | { readonly kind: "idle"; readonly sessionID: string }
  | { readonly kind: "activity"; readonly sessionID: string; readonly lastUpdatedMs: number }

type WatchState = {
  readonly messageCount: number
  readonly completed: boolean
}

const RECENT_ACTIVITY_MS = 15 * 60_000

/**
 * Polling ingress. Replaces SSE for P0: the live server's /event stream filters
 * every event against the server instance's own directory (see patch entry
 * opencode--sse-directory-filter-removal), so project events never reach an
 * external subscriber regardless of query params. Polling the authoritative
 * HTTP API is the design-compliant fallback — SSE was only ever a hint.
 *
 * Idle signal: last message is an assistant whose time.completed is set and the
 * message count has not grown since the previous poll. Busy signal: message
 * count grew. Only top-level sessions (per the child-ID set from reconcile)
 * updated within the recent-activity window are polled.
 */
export async function pollRootOnce(
  client: OpencodeClient,
  root: string,
  childIDs: ReadonlySet<string>,
  previous: Map<string, WatchState>,
  nowMs: number,
): Promise<readonly PollSignal[]> {
  const sessions = (await client.listSessions(root)).filter(
    (session: Session) =>
      session.parentID === undefined &&
      !childIDs.has(session.id) &&
      (session.timeUpdatedMs === undefined || session.timeUpdatedMs >= nowMs - RECENT_ACTIVITY_MS),
  )
  const signals: PollSignal[] = []
  const next = new Map<string, WatchState>()
  for (const session of sessions) {
    const messages = await client.listMessages(session.id, root)
    const last = messages.at(-1)
    const state: WatchState = {
      messageCount: messages.length,
      completed: last !== undefined && last.role === "assistant" && last.time.completed !== undefined,
    }
    next.set(session.id, state)
    const prior = previous.get(session.id)
    if (prior === undefined) {
      // First observation: an already-completed session idles immediately;
      // an in-flight one is busy. (A completion that happened before we started
      // watching can never "flip" otherwise.)
      signals.push(state.completed ? { kind: "idle", sessionID: session.id } : { kind: "busy", sessionID: session.id })
    } else if (state.messageCount > prior.messageCount) {
      signals.push({ kind: "busy", sessionID: session.id })
    } else if (!prior.completed && state.completed) {
      signals.push({ kind: "idle", sessionID: session.id })
    }
    if (session.timeUpdatedMs !== undefined) {
      signals.push({ kind: "activity", sessionID: session.id, lastUpdatedMs: session.timeUpdatedMs })
    }
  }
  for (const key of previous.keys()) if (!next.has(key)) previous.delete(key)
  for (const [key, state] of next) previous.set(key, state)
  return signals
}
