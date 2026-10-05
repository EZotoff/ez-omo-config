// Awaiting-operator-input detection (2026-10-05 incident, ses_ef4ef9abaffe):
// a session whose last assistant message trails a RUNNING question-tool part
// is blocked on the operator's dialog answer. The projector drops tool parts
// (projector.ts messageText keeps only text), so the tick saw a text-less
// reply, read the exchange as undelivered, and kick-started the session ~90 s
// after it asked "Push scope?". Detection must be structural, not prompt-level:
// the previous fix (epoch-2 POLICY tightening) guarded the APPROVE path only
// and the CONTINUE sibling leaked within hours.
//
// Data model (probed live 2026-10-05): question-tool part states are
// "running" (dialog open, awaiting the operator), "completed" (answered),
// "error" (aborted — e.g. metadata.interrupted with "Tool execution aborted").
// Answering a question mutates the tool part IN PLACE — the message ID never
// changes — so lastMessageID premise checks cannot see the wait. Only the
// part state can.
import type { Message, Part } from "./types"

/** Stable grep prefix for TICK_SKIPPED reasons and guard refusals. */
export const AWAITING_OPERATOR_SKIP_REASON =
  "awaiting-operator-input: question-tool dialog pending — no decision, no write"

export function isQuestionPart(part: Part): boolean {
  return part.type === "tool" && part.tool === "question"
}

const asRecord = (value: unknown): Record<string, unknown> =>
  typeof value === "object" && value !== null ? (value as Record<string, unknown>) : {}

/**
 * The trailing question-tool part of the FINAL assistant message, when it is
 * still awaiting the operator's answer. Trailing rule: the LAST question part
 * in the final assistant message decides — a terminal ask (completed/error)
 * after or instead of a running one means the wait is over; any newer user or
 * assistant message likewise. Returns undefined when the session is not blocked.
 */
export function pendingQuestionPart(messages: readonly Message[]): Part | undefined {
  const last = messages.at(-1)
  if (last === undefined || last.role !== "assistant") return undefined
  const trailing = [...last.parts].reverse().find(isQuestionPart)
  if (trailing === undefined) return undefined
  const state = asRecord(trailing.state)
  if (state["status"] !== "running") return undefined
  const metadata = asRecord(state["metadata"])
  if (metadata["interrupted"] === true) return undefined
  return trailing
}

export function awaitingOperatorAnswer(messages: readonly Message[]): boolean {
  return pendingQuestionPart(messages) !== undefined
}

/** Best-effort human rendering of the pending ask (transcripts, skip reasons). */
export function pendingQuestionText(part: Part, limit = 200): string {
  const state = asRecord(part.state)
  const input = asRecord(state["input"])
  const rawQuestions = input["questions"]
  const questions = Array.isArray(rawQuestions) ? rawQuestions.map(asRecord) : []
  const text = questions
    .map((q) => (typeof q["question"] === "string" ? q["question"] : typeof q["header"] === "string" ? q["header"] : ""))
    .filter((q) => q !== "")
    .join(" | ")
  if (text === "") return "(unparsed question payload)"
  return text.length > limit ? `${text.slice(0, limit - 1)}…` : text
}

export function pendingQuestionStartedAtMs(part: Part): number | undefined {
  const state = asRecord(part.state)
  const time = asRecord(state["time"])
  return typeof time["start"] === "number" ? time["start"] : undefined
}

/**
 * Write-time guard (layer 2): re-fetches the target's messages immediately
 * before delivery and refuses ANY supervisor-authored intervention while the
 * session trails a pending question. This is the check that catches the race
 * the decision-time suppression cannot: the operator answers mid-window, the
 * tool part completes in place (no new message ID), and the session resumes —
 * a stale-premise write would land mid-resumption. ALL FOUR intervention
 * write sites (approve/continue/steer/reformulate) must route through this;
 * tests/test_supervisor_awaiting_input.sh enforces that no raw promptAsync
 * intervention call site survives in service.ts (schema-ghost tripwire).
 */
export function createGuardedPrompt(deps: {
  readonly listMessages: (sessionID: string, root: string) => Promise<readonly Message[]>
  readonly promptAsync: (sessionID: string, root: string, text: string) => Promise<void>
}) {
  return async (sessionID: string, root: string, text: string): Promise<{ sent: true } | { sent: false; reason: string }> => {
    const messages = await deps.listMessages(sessionID, root)
    const pending = pendingQuestionPart(messages)
    if (pending !== undefined) {
      return { sent: false, reason: `${AWAITING_OPERATOR_SKIP_REASON} (${pendingQuestionText(pending, 120)})` }
    }
    await deps.promptAsync(sessionID, root, text)
    return { sent: true }
  }
}
