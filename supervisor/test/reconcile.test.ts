import { expect, test } from "bun:test"
import { changedTurnsSinceWatermark, type SessionScan } from "../src/reconcile"
import type { Message, Session, Turn } from "../src/types"

const session: Session = { id: "ses-a", directory: "/project" }
const messages: readonly Message[] = [
  { id: "u1", sessionID: "ses-a", role: "user", time: { created: 1 }, parts: [] },
  { id: "a1", sessionID: "ses-a", role: "assistant", time: { created: 2 }, parts: [] },
  { id: "u2", sessionID: "ses-a", role: "user", time: { created: 3 }, parts: [] },
  { id: "a2", sessionID: "ses-a", role: "assistant", time: { created: 4 }, parts: [] },
]
const turns: readonly Turn[] = [
  { sessionID: "ses-a", userMessageID: "u1", assistantMessageID: "a1", origin: "human", userText: "one", assistantText: "done", transcript: "one" },
  { sessionID: "ses-a", userMessageID: "u2", assistantMessageID: "a2", origin: "human", userText: "two", assistantText: "done", transcript: "two" },
]
const scan: SessionScan = { session, messages, turns, watermark: "a2" }

test("returns only sibling turns changed after the previous watermark", () => {
  expect(changedTurnsSinceWatermark("a1", scan).map((turn) => turn.userMessageID)).toEqual(["u2"])
})

test("returns no sibling delta when the watermark is current", () => {
  expect(changedTurnsSinceWatermark("a2", scan)).toEqual([])
})
