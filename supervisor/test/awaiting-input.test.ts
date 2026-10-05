// Awaiting-operator-input guard (2026-10-05 incident, ses_ef4ef9abaffe):
// the supervisor kick-started a session ~90 s after it asked the operator
// "Push scope?" via the question tool — the projector drops tool parts, so
// the tick saw a text-less reply and read the wait as an undelivered exchange.
// These tests pin the detection predicate, the write-time guard, and the
// transcript rendering that makes the wait visible to the classifier.
import { describe, expect, test } from "bun:test"
import { pendingQuestionPart, awaitingOperatorAnswer, pendingQuestionText, pendingQuestionStartedAtMs, createGuardedPrompt, AWAITING_OPERATOR_SKIP_REASON } from "../src/awaiting-input"
import { projectTurns } from "../src/projector"
import { statusSchema } from "../src/status"
import type { Message, Part } from "../src/types"

const questionPart = (id: string, messageID: string, status: string, extra: Record<string, unknown> = {}): Part => ({
  id,
  messageID,
  type: "tool",
  tool: "question",
  state: {
    status,
    input: { questions: [{ question: "Push scope?", header: "Push scope", options: [] }] },
    time: { start: 1_000 },
    ...extra,
  },
})

const textPart = (id: string, messageID: string, text: string): Part => ({ id, messageID, type: "text", text })

const message = (id: string, role: "user" | "assistant", parts: readonly Part[], completed = true): Message => ({
  id,
  sessionID: "ses-a",
  role,
  time: completed ? { created: 1, completed: 2 } : { created: 1 },
  parts,
})

const emptyRegistry = { humanMessageIDs: new Set<string>(), supervisorMessageIDs: new Set<string>() }

describe("pendingQuestionPart", () => {
  test("running trailing question → pending", () => {
    const messages = [message("u1", "user", [textPart("p0", "u1", "go")]), message("a1", "assistant", [textPart("p1", "a1", "scan done"), questionPart("p2", "a1", "running")])]
    expect(pendingQuestionPart(messages)?.id).toBe("p2")
    expect(awaitingOperatorAnswer(messages)).toBe(true)
  })
  test("text-only assistant message (the incident shape minus the tool part) → not pending", () => {
    const messages = [message("u1", "user", [textPart("p0", "u1", "go")]), message("a1", "assistant", [textPart("p1", "a1", "")])]
    expect(awaitingOperatorAnswer(messages)).toBe(false)
  })
  test("completed question (answered) → not pending", () => {
    const messages = [message("u1", "user", [textPart("p0", "u1", "go")]), message("a1", "assistant", [questionPart("p1", "a1", "completed", { result: { answers: [] } })])]
    expect(awaitingOperatorAnswer(messages)).toBe(false)
  })
  test("errored question (aborted) → not pending", () => {
    const messages = [message("u1", "user", [textPart("p0", "u1", "go")]), message("a1", "assistant", [questionPart("p1", "a1", "error", { error: "Tool execution aborted", metadata: { interrupted: true } })])]
    expect(awaitingOperatorAnswer(messages)).toBe(false)
  })
  test("trailing rule: last question part decides — terminal last hides an earlier running ask", () => {
    const messages = [message("u1", "user", [textPart("p0", "u1", "go")]), message("a1", "assistant", [questionPart("p1", "a1", "running"), questionPart("p2", "a1", "completed")])]
    expect(awaitingOperatorAnswer(messages)).toBe(false)
  })
  test("trailing rule: running last wins over an earlier terminal ask (re-ask after failure)", () => {
    const messages = [message("u1", "user", [textPart("p0", "u1", "go")]), message("a1", "assistant", [questionPart("p1", "a1", "error"), questionPart("p2", "a1", "running")])]
    expect(pendingQuestionPart(messages)?.id).toBe("p2")
  })
  test("newer user message after the question (operator answered) → not pending", () => {
    const messages = [
      message("u1", "user", [textPart("p0", "u1", "go")]),
      message("a1", "assistant", [questionPart("p1", "a1", "running")]),
      message("u2", "user", [textPart("p2", "u2", "Tier A")]),
    ]
    expect(awaitingOperatorAnswer(messages)).toBe(false)
  })
  test("question in an earlier assistant run, later clean assistant message → not pending", () => {
    const messages = [
      message("u1", "user", [textPart("p0", "u1", "go")]),
      message("a1", "assistant", [questionPart("p1", "a1", "running")]),
      message("a2", "assistant", [textPart("p2", "a2", "continued work")]),
    ]
    expect(awaitingOperatorAnswer(messages)).toBe(false)
  })
  test("empty transcript → not pending", () => {
    expect(awaitingOperatorAnswer([])).toBe(false)
  })
  test("exposes the question start time for age reporting", () => {
    const part = pendingQuestionPart([message("a1", "assistant", [questionPart("p1", "a1", "running")])])
    expect(pendingQuestionStartedAtMs(part!)).toBe(1_000)
  })
})

describe("pendingQuestionText", () => {
  test("extracts question text from the tool input", () => {
    const part = questionPart("p1", "a1", "running")
    expect(pendingQuestionText(part)).toBe("Push scope?")
  })
  test("falls back when the payload is unparseable", () => {
    const part: Part = { id: "p1", messageID: "a1", type: "tool", tool: "question", state: { status: "running" } }
    expect(pendingQuestionText(part)).toContain("unparsed")
  })
})

describe("createGuardedPrompt (write-time guard, layer 2)", () => {
  const deps = (messages: readonly Message[]) => {
    const delivered: string[] = []
    return {
      delivered,
      guard: createGuardedPrompt({
        listMessages: async () => messages,
        promptAsync: async (_sessionID, _root, text) => { delivered.push(text) },
      }),
    }
  }
  test("refuses and does NOT write when the session trails a pending question", async () => {
    const messages = [message("u1", "user", [textPart("p0", "u1", "go")]), message("a1", "assistant", [questionPart("p1", "a1", "running")])]
    const { guard, delivered } = deps(messages)
    const outcome = await guard("ses-a", "/root", "[supervisor] (continue) stalled")
    expect(outcome.sent).toBe(false)
    if (!outcome.sent) expect(outcome.reason).toContain("awaiting-operator-input")
    expect(delivered).toEqual([])
  })
  test("delivers when the question is answered (in-place part completion, message ID unchanged)", async () => {
    const messages = [message("u1", "user", [textPart("p0", "u1", "go")]), message("a1", "assistant", [questionPart("p1", "a1", "completed")])]
    const { guard, delivered } = deps(messages)
    const outcome = await guard("ses-a", "/root", "[supervisor] (continue) stalled")
    expect(outcome.sent).toBe(true)
    expect(delivered).toEqual(["[supervisor] (continue) stalled"])
  })
  test("skip reason carries the stable grep prefix", () => {
    expect(AWAITING_OPERATOR_SKIP_REASON.startsWith("awaiting-operator-input")).toBe(true)
  })
})

describe("projector renders the pending ask (layer 3)", () => {
  test("trailing running question is visible in the transcript and flagged on the turn", () => {
    const turns = projectTurns(
      [message("u1", "user", [textPart("p0", "u1", "scan the repo")]), message("a1", "assistant", [textPart("p1", "a1", "done"), questionPart("p2", "a1", "running")])],
      emptyRegistry,
    )
    expect(turns[0]?.awaitingOperatorAnswer).toBe(true)
    expect(turns[0]?.transcript).toContain("[awaiting operator answer via question tool: Push scope?]")
  })
  test("answered question leaves the transcript clean and the flag unset", () => {
    const turns = projectTurns(
      [message("u1", "user", [textPart("p0", "u1", "scan the repo")]), message("a1", "assistant", [questionPart("p1", "a1", "completed")])],
      emptyRegistry,
    )
    expect(turns[0]?.awaitingOperatorAnswer ?? false).toBe(false)
    expect(turns[0]?.transcript).not.toContain("awaiting operator answer")
  })
})

describe("status schema accepts the awaitingOperator counter (safety valve)", () => {
  test("parses with count only", () => {
    const parsed = statusSchema.parse({ lastReconcile: null, queueDepths: {}, ticksByAction: {}, unknownOriginRate: 0, machineMarkedRate: 0, awaitingOperator: { count: 3 } })
    expect(parsed.awaitingOperator?.count).toBe(3)
  })
  test("parses with the oldest-question age", () => {
    const parsed = statusSchema.parse({ lastReconcile: null, queueDepths: {}, ticksByAction: {}, unknownOriginRate: 0, machineMarkedRate: 0, awaitingOperator: { count: 1, oldestQuestionStartMs: 1_000 } })
    expect(parsed.awaitingOperator?.oldestQuestionStartMs).toBe(1_000)
  })
})
