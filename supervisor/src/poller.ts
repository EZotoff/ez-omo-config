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
  /** Session-listing updated timestamp last seen for this session (cheap signal). */
  lastUpdatedMs?: number
  /** Whether the expensive full-transcript classification fetch has run. */
  fetched: boolean
  /** Set by the cheap-listing advance path: the session moved but completion was
   *  not yet classified from the transcript. The next quiet poll must bypass the
   *  unchanged short-circuit ONCE to classify idle vs still-busy (2026-10-02
   *  bonsai-stall fix: without this, between-poll completions were invisible
   *  until the 15-minute stall escape, if polls succeeded at all). */
  pendingClassification?: boolean
}

const EMPTY_STATE: WatchState = { messageCount: 0, completed: false, stallFired: false, fetched: false }

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
  // Tracked sessions stay pollable even outside the recent-activity window:
  // an incomplete turn quiescent past the threshold is exactly the stall case
  // and must not become invisible (2026-09-30 regression from the window filter).
  const eligible = (session: Session): boolean =>
    session.parentID === undefined &&
    !childIDs.has(session.id) &&
    (previous.has(session.id) || session.timeUpdatedMs === undefined || session.timeUpdatedMs >= nowMs - RECENT_ACTIVITY_MS)
  const sessions = (await client.listSessions(root)).filter(eligible)
  const signals: PollSignal[] = []
  const next = new Map<string, WatchState>()
  for (const session of sessions) {
    const updated = session.timeUpdatedMs
    const prior = previous.get(session.id)
    // Activity detection from the CHEAP session listing: an advancing updated
    // timestamp means the session is producing — no transcript fetch needed.
    // The expensive listMessages runs ONLY on quiescence, to classify idle
    // (assistant completed) vs stalled. Pulling full transcripts for every
    // hot session every tick was the loopback firehose (17.6 MiB/s measured
    // 2026-09-29: multi-MB bench transcripts re-downloaded every 20s).
    const advanced = prior?.lastUpdatedMs !== undefined && updated !== undefined && updated > prior.lastUpdatedMs
    if (prior !== undefined && advanced) {
      next.set(session.id, {
        messageCount: prior.messageCount,
        completed: false,
        stallFired: false, // activity resets the stall episode
        lastUpdatedMs: updated,
        fetched: prior.fetched,
        pendingClassification: true,
      })
      signals.push({ kind: "busy", sessionID: session.id })
      if (updated !== undefined) {
        signals.push({ kind: "activity", sessionID: session.id, lastUpdatedMs: updated })
      }
      continue
    }
    // Quiescent session: fetch the transcript ONLY if it changed since the last
    // classification (or was never fetched). Re-fetching an unchanged multi-MB
    // transcript every tick was the residual firehose (6.5 MiB/5s measured).
    if (prior?.fetched && prior.pendingClassification !== true && prior.lastUpdatedMs === updated) {
      // Unchanged session: no re-fetch, but the stall check must still run —
      // quiescence is precisely the no-change case (dead-code regression:
      // the short-circuit skipped the stall branch entirely).
      let state = { ...prior }
      if (!prior.completed && !prior.stallFired) {
        const quiescentFor = nowMs - (updated ?? nowMs)
        if (quiescentFor >= stallAfterMs) {
          state = { ...prior, stallFired: true }
          signals.push({ kind: "stalled", sessionID: session.id })
        }
      }
      next.set(session.id, state)
      if (updated !== undefined) {
        signals.push({ kind: "activity", sessionID: session.id, lastUpdatedMs: updated })
      }
      continue
    }
    const messages = await client.listMessages(session.id, root)
    const last = messages.at(-1)
    const state: WatchState = {
      messageCount: messages.length,
      completed: last !== undefined && last.role === "assistant" && last.time.completed !== undefined,
      stallFired: previous.get(session.id)?.stallFired ?? false,
      ...(updated === undefined ? {} : { lastUpdatedMs: updated }),
      fetched: true,
      pendingClassification: false,
    }
    next.set(session.id, state)
    if (prior === undefined) {
      // First observation: an already-completed session idles immediately;
      // an in-flight one is busy. (A completion that happened before we started
      // watching can never "flip" otherwise.)
      signals.push(state.completed ? { kind: "idle", sessionID: session.id } : { kind: "busy", sessionID: session.id })
    } else if (state.messageCount > prior.messageCount) {
      // 2026-10-02 bonsai-stall fix: a growth poll whose last message is an
      // already-completed assistant reply means the whole turn started AND
      // finished between two polls. Emitting `busy` here (the old behavior)
      // made the completion structurally invisible: the flip detector below
      // requires prior.completed === false, so no idle signal ever fired, no
      // GRACE re-entry, no tick — sessions silently dropped out of the tick
      // pipeline for every such turn.
      signals.push(state.completed ? { kind: "idle", sessionID: session.id } : { kind: "busy", sessionID: session.id })
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
