import { describe, expect, test } from "bun:test"
import { pickTarget } from "../src/targets"
import type { Message, Turn } from "../src/types"

const turn = (userMessageID: string, assistantMessageID: string | undefined, origin: Turn["origin"]): Turn =>
  assistantMessageID === undefined
    ? { sessionID: "ses-a", userMessageID, origin, userText: "u", assistantText: "a", transcript: "t" }
    : { sessionID: "ses-a", userMessageID, assistantMessageID, origin, userText: "u", assistantText: "a", transcript: "t" }
const message = (id: string, role: "user" | "assistant", extra: { error?: unknown; finish?: string } = {}): Message => ({
  id, sessionID: "ses-a", role, time: { created: 1 }, parts: [],
  ...(extra.error === undefined ? {} : { error: extra.error }),
  ...(extra.finish === undefined ? {} : { finish: extra.finish }),
})

describe("pickTarget", () => {
  test("selects the last human turn when its reply is the session's last message", () => {
    const turns = [turn("u1", "a1", "human"), turn("u2", "a2", "unknown")]
    expect(pickTarget(turns, [message("u1", "user"), message("a1", "assistant"), message("u2", "user"), message("a2", "assistant")])).toMatchObject({ target: { userMessageID: "u2" } })
  })
  test("stands down when a ralph push arrived after the target reply", () => {
    const turns = [turn("u1", "a1", "human")]
    const messages = [message("u1", "user"), message("a1", "assistant"), message("ralph", "user"), message("a2", "assistant")]
    expect(pickTarget(turns, messages)).toMatchObject({ rejected: "stale-target" })
  })
  test("stands down when the last turn is machine-driven", () => {
    const turns = [turn("u1", "a1", "human"), turn("r1", "a2", "machine-template")]
    expect(pickTarget(turns, [message("u1", "user"), message("a1", "assistant"), message("r1", "user"), message("a2", "assistant")])).toMatchObject({ rejected: "origin-excluded" })
  })
  test("stands down when the human turn has no completed reply", () => {
    const turns = [turn("u1", undefined, "human")]
    expect(pickTarget(turns, [message("u1", "user")])).toMatchObject({ rejected: "stale-target" })
  })
  test("never selects an operator-aborted turn (D295 abort guard)", () => {
    const turns = [turn("u1", "a1", "human")]
    const messages = [message("u1", "user"), message("a1", "assistant", { finish: "aborted" })]
    expect(pickTarget(turns, messages)).toMatchObject({ rejected: "aborted" })
  })
  test("keeps an errored turn selectable as kick-start candidate (D244)", () => {
    const turns = [turn("u1", "a1", "human")]
    const messages = [message("u1", "user"), message("a1", "assistant", { error: { name: "APIError", message: "model not found" } })]
    expect(pickTarget(turns, messages)).toMatchObject({ target: { userMessageID: "u1" } })
  })
  test("aborted guard applies to the last turn only when it is the reply (earlier aborted, later healthy wins)", () => {
    const turns = [turn("u1", "a1", "human"), turn("u2", "a2", "human")]
    const messages = [message("u1", "user"), message("a1", "assistant", { finish: "aborted" }), message("u2", "user"), message("a2", "assistant")]
    expect(pickTarget(turns, messages)).toMatchObject({ target: { userMessageID: "u2" } })
  })
})
