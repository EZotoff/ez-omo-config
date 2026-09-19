import { describe, expect, test } from "bun:test"
import { ActivityGate } from "../src/poller"
import { assistantRunFor, classifyRunHealth, continueEligible, isAbortError, turnHealth } from "../src/health"
import { pickTarget } from "../src/targets"
import type { Message, Part, Turn } from "../src/types"

const part = (text?: string): Part => ({ id: "p", messageID: "m", type: "text", ...(text === undefined ? {} : { text }) })
const message = (id: string, role: "user" | "assistant", fields: { text?: string; error?: unknown; finish?: string; completed?: number } = {}): Message => ({
  id,
  sessionID: "ses-a",
  role,
  time: { created: 1, ...(fields.completed === undefined ? {} : { completed: fields.completed }) },
  parts: fields.text === undefined ? [] : [part(fields.text)],
  ...(fields.error === undefined ? {} : { error: fields.error }),
  ...(fields.finish === undefined ? {} : { finish: fields.finish }),
})
const turn = (userMessageID: string, assistantMessageID: string | undefined): Turn =>
  assistantMessageID === undefined
    ? { sessionID: "ses-a", userMessageID, origin: "human", userText: "u", assistantText: "a", transcript: "t" }
    : { sessionID: "ses-a", userMessageID, assistantMessageID, origin: "human", userText: "u", assistantText: "a", transcript: "t" }

describe("classifyRunHealth", () => {
  test("healthy: completed assistant run with text", () => {
    expect(classifyRunHealth([message("a1", "assistant", { text: "done", completed: 2 })])).toBe("healthy")
  })
  test("stalled: completed assistant run with no text parts", () => {
    expect(classifyRunHealth([message("a1", "assistant", { completed: 2 })])).toBe("stalled")
  })
  test("stalled: empty run (user message with no assistant reply)", () => {
    expect(classifyRunHealth([])).toBe("stalled")
  })
  test("aborted: finish=aborted (D295 shape)", () => {
    expect(classifyRunHealth([message("a1", "assistant", { finish: "aborted", completed: 2 })])).toBe("aborted")
  })
  test("aborted: MessageAbortedError in error field", () => {
    expect(classifyRunHealth([message("a1", "assistant", { error: { name: "MessageAbortedError", message: "aborted" }, completed: 2 })])).toBe("aborted")
  })
  test("errored: APIError in error field (D244 shape)", () => {
    expect(classifyRunHealth([message("a1", "assistant", { error: { name: "APIError", message: "model not found" }, completed: 2 })])).toBe("errored")
  })
  test("error precedence over no-text stall", () => {
    expect(classifyRunHealth([message("a1", "assistant", { error: { name: "APIError" }, completed: 2 })])).toBe("errored")
  })
})

describe("isAbortError", () => {
  test("matches MessageAbortedError name only", () => {
    expect(isAbortError({ name: "MessageAbortedError" })).toBe(true)
    expect(isAbortError({ name: "APIError" })).toBe(false)
    expect(isAbortError("aborted")).toBe(false)
    expect(isAbortError(null)).toBe(false)
  })
})

describe("assistantRunFor / turnHealth", () => {
  test("extracts the contiguous assistant run after the turn's user message", () => {
    const messages = [message("u1", "user", { text: "continue" }), message("a1", "assistant", { text: "thinking" }), message("a2", "assistant", { text: "answer", completed: 3 })]
    const run = assistantRunFor(turn("u1", "a2"), messages)
    expect(run.map((entry) => entry.id)).toEqual(["a1", "a2"])
    expect(turnHealth(turn("u1", "a2"), messages)).toBe("healthy")
  })
  test("turn without assistant reply classifies stalled", () => {
    expect(turnHealth(turn("u1", undefined), [message("u1", "user", { text: "continue" })])).toBe("stalled")
  })
})

describe("pickTarget abort guard (D295 fixture)", () => {
  test("aborted turn is never a target (operator stopped it)", () => {
    const target = turn("u1", "a1")
    const turns = [target]
    const messages = [message("u1", "user", { text: "continue" }), message("a1", "assistant", { finish: "aborted", completed: 2 })]
    expect(turnHealth(target, messages)).toBe("aborted")
    expect(pickTarget(turns, messages)).toBeUndefined()
  })
  test("MessageAbortedError error field equally guards", () => {
    const turns = [turn("u1", "a1")]
    const messages = [message("u1", "user", { text: "continue" }), message("a1", "assistant", { error: { name: "MessageAbortedError" }, completed: 2 })]
    expect(pickTarget(turns, messages)).toBeUndefined()
  })
})

describe("pickTarget errored eligibility (D244 fixture)", () => {
  test("APIError turn stays a kick-start candidate", () => {
    const target = turn("u1", "a1")
    const turns = [target]
    const messages = [message("u1", "user", { text: "keep going" }), message("a1", "assistant", { error: { name: "APIError", message: "model not found" }, completed: 2 })]
    expect(turnHealth(target, messages)).toBe("errored")
    expect(pickTarget(turns, messages)?.userMessageID).toBe("u1")
  })
})

describe("continueEligible", () => {
  test("aborted is never eligible, even when quiescent", () => {
    expect(continueEligible("aborted", true)).toBe(false)
  })
  test("errored, stalled, and healthy are eligible when quiescent", () => {
    expect(continueEligible("errored", true)).toBe(true)
    expect(continueEligible("stalled", true)).toBe(true)
    expect(continueEligible("healthy", true)).toBe(true)
  })
  test("non-quiescent sessions are never eligible", () => {
    expect(continueEligible("errored", false)).toBe(false)
    expect(continueEligible("healthy", false)).toBe(false)
  })
})
describe("ActivityGate quiescence transitions", () => {
  const GRACE = 60_000
  test("unobserved session is not quiescent", () => {
    const gate = new ActivityGate()
    expect(gate.isQuiescent("ses-a", 1_000_000, GRACE)).toBe(false)
  })
  test("quiescent after grace with no movement", () => {
    const gate = new ActivityGate()
    gate.observe([{ kind: "activity", sessionID: "ses-a", lastUpdatedMs: 1_000_000 }], 1_020_000)
    expect(gate.isQuiescent("ses-a", 1_000_000 + GRACE - 1, GRACE)).toBe(false)
    expect(gate.isQuiescent("ses-a", 1_000_000 + GRACE, GRACE)).toBe(true)
  })
  test("message growth (busy) re-arms the gate at poll time", () => {
    const gate = new ActivityGate()
    gate.observe([{ kind: "activity", sessionID: "ses-a", lastUpdatedMs: 1_000_000 }], 1_020_000)
    expect(gate.isQuiescent("ses-a", 1_100_000, GRACE)).toBe(true)
    gate.observe([{ kind: "busy", sessionID: "ses-a" }], 1_100_000)
    expect(gate.isQuiescent("ses-a", 1_100_000 + GRACE - 1, GRACE)).toBe(false)
    expect(gate.isQuiescent("ses-a", 1_100_000 + GRACE, GRACE)).toBe(true)
  })
  test("timeUpdated movement re-arms the gate dated by the movement itself", () => {
    const gate = new ActivityGate()
    gate.observe([{ kind: "activity", sessionID: "ses-a", lastUpdatedMs: 1_000_000 }], 1_020_000)
    gate.observe([{ kind: "activity", sessionID: "ses-a", lastUpdatedMs: 1_050_000 }], 1_060_000)
    expect(gate.isQuiescent("ses-a", 1_050_000 + GRACE - 1, GRACE)).toBe(false)
    expect(gate.isQuiescent("ses-a", 1_050_000 + GRACE, GRACE)).toBe(true)
  })
  test("unchanged timeUpdated across polls does not re-arm", () => {
    const gate = new ActivityGate()
    gate.observe([{ kind: "activity", sessionID: "ses-a", lastUpdatedMs: 1_000_000 }], 1_020_000)
    gate.observe([{ kind: "activity", sessionID: "ses-a", lastUpdatedMs: 1_000_000 }], 1_200_000)
    expect(gate.isQuiescent("ses-a", 1_200_000, GRACE)).toBe(true)
  })
})
