import type { Message, Turn } from "./types"

/**
 * Operator-attention-point selection. The supervisor replaces the operator's
 * attention, so it must tick ONLY where the operator's attention would be
 * required: the session has gone idle with the target reply as its LAST
 * message. If anything (a ralph push, a nudge, another user message) arrived
 * after the target reply, the moment has already been handled by whatever
 * pushed next — the supervisor stands down for that idle event.
 */
export function pickTarget(turns: readonly Turn[], messages: readonly Message[]): Turn | undefined {
  const lastMessageID = messages.at(-1)?.id
  if (lastMessageID === undefined) return undefined
  const candidates = turns.filter(
    (turn) =>
      (turn.origin === "human" || turn.origin === "unknown") &&
      turn.assistantMessageID === lastMessageID,
  )
  return candidates.at(-1)
}
