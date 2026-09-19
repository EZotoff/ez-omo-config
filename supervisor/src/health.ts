import type { Message, Turn } from "./types"

export type SessionHealth = "healthy" | "stalled" | "errored" | "aborted"

const hasTextParts = (message: Message): boolean =>
  message.parts.some((part) => part.type === "text" && (part.text ?? "") !== "")

/**
 * Operator-stopped turns carry MessageAbortedError in message metadata; the
 * abort marker also appears as finish=aborted when the error object is absent.
 */
export function isAbortError(error: unknown): boolean {
  if (typeof error !== "object" || error === null) return false
  return "name" in error && error.name === "MessageAbortedError"
}

/** Contiguous assistant run answering the turn's user message (empty when absent). */
export function assistantRunFor(turn: Turn, messages: readonly Message[]): readonly Message[] {
  if (turn.assistantMessageID === undefined) return []
  const end = messages.findIndex((message) => message.id === turn.assistantMessageID)
  if (end === -1) return []
  const start = messages.findLastIndex((message, index) => index < end && message.role === "user")
  return messages.slice(start === -1 ? 0 : start + 1, end + 1)
}

export function classifyRunHealth(run: readonly Message[]): SessionHealth {
  const last = run.at(-1)
  if (last === undefined || last.role !== "assistant") return "stalled"
  if (last.finish === "aborted") return "aborted"
  if (last.error !== undefined) return isAbortError(last.error) ? "aborted" : "errored"
  if (last.time.completed !== undefined && !hasTextParts(last)) return "stalled"
  return "healthy"
}

export function turnHealth(turn: Turn, messages: readonly Message[]): SessionHealth {
  return classifyRunHealth(assistantRunFor(turn, messages))
}

/**
 * CONTINUE eligibility (judgment INPUT only — this never writes): operator-
 * aborted turns are never kick-start targets (D295); everything else requires
 * quiescence so an actively running session is never nudged.
 */
export function continueEligible(health: SessionHealth, quiescent: boolean): boolean {
  return health !== "aborted" && quiescent
}
