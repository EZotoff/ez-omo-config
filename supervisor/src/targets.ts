import { classifyRunHealth, assistantRunFor } from "./health"
import type { Message, Turn } from "./types"

/**
 * Operator-attention-point selection. The supervisor replaces the operator's
 * attention, so it must tick ONLY where the operator's attention would be
 * required: the session has gone idle with the target reply as its LAST
 * message. If anything (a ralph push, a nudge, another user message) arrived
 * after the target reply, the moment has already been handled by whatever
 * pushed next — the supervisor stands down for that idle event.
 */
export function pickTarget(turns: readonly Turn[], messages: readonly Message[], options: { readonly sessionProtected?: boolean } = {}): Turn | undefined {
  // Protection overlay (D295): an operator-protected session is never a kick-start target.
  if (options.sessionProtected === true) return undefined
  const lastMessageID = messages.at(-1)?.id
  if (lastMessageID === undefined) return undefined
  const candidates = turns.filter(
    (turn) =>
      (turn.origin === "human" || turn.origin === "unknown") &&
      turn.assistantMessageID === lastMessageID,
  )
  // Abort guard (D295): an operator-stopped turn is never an attention point.
  // Errored/stalled runs stay eligible — they are the kick-start candidates.
  return candidates.filter((turn) => classifyRunHealth(assistantRunFor(turn, messages)) !== "aborted").at(-1)
}
