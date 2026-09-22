import type { OpencodeClient } from "./client"
import type { Session } from "./types"

export type PollSignal =
  | { readonly kind: "busy"; readonly sessionID: string }
  | { readonly kind: "idle"; readonly sessionID: string }
  | { readonly kind: "stalled"; readonly sessionID: string }
  | { readonly kind: "activity"; readonly sessionID: string; readonly lastUpdatedMs: number }

export type WatchState = {
  readonly messageCount: number
  readonly completed: boolean
  /** A stall was already reported for this episode; reset on message growth. */
  stallFired: boolean
}

const EMPTY_STATE: WatchState = { messageCount: 0, completed: false, stallFired: false }

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
 * count grew. STALL signal: an INCOMPLETE turn (assistant never completed —
 * wedged stream, hung generation) quiescent past stallAfterMs — this class
 * produces no idle flip on its own and would otherwise be invisible forever
 * (live case 2026-09-20: glm-5.3-flash stream wedged 25+ minutes). Fires once
 * per stall episode; message growth resets it. Only top-level sessions (per the
 * child-ID set from reconcile) updated within the recent-activity window are
 * polled.
 */
export async function pollRootOnce(
  client: OpencodeClient,
  root: string,
  childIDs: ReadonlySet<string>,
  previous: Map<string, WatchState>,
  nowMs: number,
  stallAfterMs = 15 * 60_000,
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
      stallFired: previous.get(session.id)?.stallFired ?? false,
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
      // Growth resets the stall episode.
      state.stallFired = false
    } else if (!prior.completed && state.completed) {
      signals.push({ kind: "idle", sessionID: session.id })
    } else if (!state.completed && !state.stallFired) {
      const quiescentFor = nowMs - (session.timeUpdatedMs ?? nowMs)
      if (quiescentFor >= stallAfterMs) {
        state.stallFired = true
        signals.push({ kind: "stalled", sessionID: session.id })
      }
    }
    if (session.timeUpdatedMs !== undefined) {
      signals.push({ kind: "activity", sessionID: session.id, lastUpdatedMs: session.timeUpdatedMs })
    }
  }
  for (const key of previous.keys()) if (!next.has(key)) previous.delete(key)
  for (const [key, state] of next) previous.set(key, state)
  return signals
}

/**
 * CONTINUE quiescence gate. Consumes the `activity` poll signal (plus busy)
 * to decide whether a session has been still long enough to be kick-started:
 * no message growth and no timeUpdated movement for >= grace period. A session
 * never observed is NOT quiescent — a kick-start requires evidence of stillness.
 */
export class ActivityGate {
  private readonly lastUpdatedMs = new Map<string, number>()
  private readonly movedAtMs = new Map<string, number>()

  observe(signals: readonly PollSignal[], nowMs: number): void {
    for (const signal of signals) {
      if (signal.kind === "busy") {
        // Message-count growth: movement is known no later than the poll that saw it.
        this.movedAtMs.set(signal.sessionID, Math.max(this.movedAtMs.get(signal.sessionID) ?? 0, nowMs))
      } else if (signal.kind === "activity") {
        const prior = this.lastUpdatedMs.get(signal.sessionID)
        if (prior !== signal.lastUpdatedMs) {
          // timeUpdated movement: dated by the movement itself, not the poll.
          this.movedAtMs.set(signal.sessionID, Math.max(this.movedAtMs.get(signal.sessionID) ?? 0, signal.lastUpdatedMs))
        }
        this.lastUpdatedMs.set(signal.sessionID, signal.lastUpdatedMs)
      }
    }
  }

  isQuiescent(sessionID: string, nowMs: number, graceMs: number): boolean {
    const movedAt = this.movedAtMs.get(sessionID)
    return movedAt !== undefined && nowMs - movedAt >= graceMs
  }
}
