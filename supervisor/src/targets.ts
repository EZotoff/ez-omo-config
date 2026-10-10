import { classifyRunHealth, assistantRunFor } from "./health"
import type { Message, Turn, TargetSelection } from "./types"

/**
 * Operator-attention-point selection. The supervisor replaces the operator's
 * attention, so it must tick ONLY where the operator's attention would be
 * required: the session has gone idle with the target reply as its LAST
 * message. If anything (a ralph push, a nudge, another user message) arrived
 * after the target reply, the moment has already been handled by whatever
 * pushed next — the supervisor stands down for that idle event.
 */
export function pickTarget(turns: readonly Turn[], messages: readonly Message[], options: { readonly sessionProtected?: boolean; readonly adjudicateMachineOrigin?: boolean } = {}): TargetSelection {
  // Protection overlay (D295): an operator-protected session is never a kick-start target.
  if (options.sessionProtected === true) return { rejected: "protected", text: "session is operator-protected" }
  const lastMessageID = messages.at(-1)?.id
  if (lastMessageID === undefined || turns.length === 0) return { rejected: "missing-context", text: "no messages or projected turns available" }
  const target = turns.findLast((turn) => turn.assistantMessageID === lastMessageID)
  if (target === undefined) return { rejected: "stale-target", text: "target is not the session's last message (native continuation or newer turn intervened)" }
  // Abort guard (D295): an operator-stopped turn is never an attention point.
  // Errored/stalled runs stay eligible — they are the kick-start candidates.
  if (classifyRunHealth(assistantRunFor(target, messages)) === "aborted") return { rejected: "aborted", text: "last assistant run was operator-aborted" }
  if (options.adjudicateMachineOrigin !== true && target.origin !== "human" && target.origin !== "unknown") {
    return { rejected: "origin-excluded", text: `target kickoff origin ${target.origin} is excluded from adjudication` }
  }
  return { target }
}
