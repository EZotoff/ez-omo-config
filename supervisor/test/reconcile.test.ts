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

test("reconcileRoot isolates a failing transcript fetch instead of throwing", async () => {
  const { reconcileRoot } = await import("../src/reconcile")
  const sessions: Session[] = [
    { id: "ses-ok", directory: "/project", timeUpdatedMs: Date.now() },
    { id: "ses-bad", directory: "/project", timeUpdatedMs: Date.now() },
  ]
  const client = {
    listSessions: async () => sessions,
    listMessages: async (sessionID: string) => {
      if (sessionID === "ses-bad") throw new Error("transient API failure")
      return [{ id: "u1", sessionID, role: "user", time: { created: 1 }, parts: [] }] as never
    },
  }
  const manifest = await reconcileRoot(client as never, "/project", { humanMessageIDs: new Set(), supervisorMessageIDs: new Set() }, { initialWindowDays: 7, fetchConcurrency: 2 })
  expect(manifest.complete).toBe(true)
  expect(manifest.sessions.map((entry) => entry.session.id)).toEqual(["ses-ok"])
  expect(manifest.fetchErrors).toHaveLength(1)
  expect(manifest.fetchErrors[0]?.sessionID).toBe("ses-bad")
})
