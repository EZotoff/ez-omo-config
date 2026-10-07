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

const backoffSessions = (): Session[] => [
  { id: "ses-bad", directory: "/project", timeUpdatedMs: 0 },
]

const backoffClient = (behaviour: (sessionID: string) => Promise<unknown>) => ({
  listSessions: async () => backoffSessions(),
  listMessages: behaviour,
})

test("session backoff: 3 consecutive failures block the session with a 60s first delay", async () => {
  const { reconcileRoot, SessionBackoff } = await import("../src/reconcile")
  let badCalls = 0
  const client = backoffClient(async () => {
    badCalls += 1
    throw new Error("transient API failure")
  })
  const sessionBackoff = new SessionBackoff()
  let clock = 1_000_000
  const run = () => reconcileRoot(client as never, "/project", { humanMessageIDs: new Set(), supervisorMessageIDs: new Set() }, { initialWindowDays: 7, fetchConcurrency: 2, nowMs: () => clock, sessionBackoff })
  await run()
  await run()
  expect(sessionBackoff.isBlocked("ses-bad", clock)).toBe(false)
  const beforeThird = clock
  await run()
  expect(badCalls).toBe(3)
  expect(sessionBackoff.isBlocked("ses-bad", clock)).toBe(true)
  expect((sessionBackoff.blockedUntil("ses-bad") ?? NaN) - beforeThird).toBe(60_000)
  clock += 30_000
  const fourth = await run()
  expect(badCalls).toBe(3)
  expect(fourth.sessions).toHaveLength(0)
  expect(fourth.fetchErrors).toHaveLength(0)
})

test("session backoff: entered fires exactly once per entry, no repeats while continuously failing", async () => {
  const { reconcileRoot, SessionBackoff } = await import("../src/reconcile")
  const client = backoffClient(async () => {
    throw new Error("transient API failure")
  })
  const sessionBackoff = new SessionBackoff()
  let clock = 1_000_000
  const run = () => reconcileRoot(client as never, "/project", { humanMessageIDs: new Set(), supervisorMessageIDs: new Set() }, { initialWindowDays: 7, fetchConcurrency: 2, nowMs: () => clock, sessionBackoff })
  await run()
  await run()
  const third = await run()
  expect(third.backoffEntered).toEqual(["ses-bad"])
  clock = (sessionBackoff.blockedUntil("ses-bad") ?? 0) + 1_000
  const afterExpiry = await run()
  expect(afterExpiry.fetchErrors).toHaveLength(1)
  expect((sessionBackoff.blockedUntil("ses-bad") ?? NaN) - clock).toBe(120_000)
  expect(afterExpiry.backoffEntered).toHaveLength(0)
  clock = (sessionBackoff.blockedUntil("ses-bad") ?? 0) + 1_000
  const again = await run()
  expect(again.backoffEntered).toHaveLength(0)
  expect(again.backoffRecovered).toHaveLength(0)
})

test("session backoff: success after backoff recovers once and re-arms the failure cycle", async () => {
  const { reconcileRoot, SessionBackoff } = await import("../src/reconcile")
  let failing = true
  const client = backoffClient(async (sessionID: string) => {
    if (failing) throw new Error("transient API failure")
    return [{ id: "u1", sessionID, role: "user", time: { created: 1 }, parts: [] }] as never
  })
  const sessionBackoff = new SessionBackoff()
  let clock = 1_000_000
  const run = () => reconcileRoot(client as never, "/project", { humanMessageIDs: new Set(), supervisorMessageIDs: new Set() }, { initialWindowDays: 7, fetchConcurrency: 2, nowMs: () => clock, sessionBackoff })
  for (let i = 0; i < 3; i += 1) await run()
  clock = (sessionBackoff.blockedUntil("ses-bad") ?? 0) + 1_000
  failing = false
  const recovered = await run()
  expect(recovered.backoffRecovered).toEqual(["ses-bad"])
  expect(sessionBackoff.isBlocked("ses-bad", clock)).toBe(false)
  expect(recovered.sessions.map((entry) => entry.session.id)).toEqual(["ses-bad"])
  failing = true
  for (let i = 0; i < 3; i += 1) await run()
  expect(sessionBackoff.isBlocked("ses-bad", clock)).toBe(true)
  clock = (sessionBackoff.blockedUntil("ses-bad") ?? 0) + 1_000
  failing = false
  const second = await run()
  expect(second.backoffRecovered).toEqual(["ses-bad"])
  expect(second.backoffEntered).toHaveLength(0)
})

test("session backoff: blocked parent stays out of sessions/fetchErrors but keeps its child non-top-level", async () => {
  const { reconcileRoot, SessionBackoff } = await import("../src/reconcile")
  const sessions: Session[] = [
    { id: "ses-parent", directory: "/project", timeUpdatedMs: 0 },
    { id: "ses-child", directory: "/project", timeUpdatedMs: 0, parentID: "ses-parent" },
  ]
  const client = {
    listSessions: async () => sessions,
    listMessages: async (sessionID: string) => {
      if (sessionID === "ses-parent") throw new Error("transient API failure")
      return [{ id: "u1", sessionID, role: "user", time: { created: 1 }, parts: [] }] as never
    },
  }
  const sessionBackoff = new SessionBackoff()
  let clock = 1_000_000
  const run = () => reconcileRoot(client as never, "/project", { humanMessageIDs: new Set(), supervisorMessageIDs: new Set() }, { initialWindowDays: 7, fetchConcurrency: 2, nowMs: () => clock, sessionBackoff })
  for (let i = 0; i < 3; i += 1) await run()
  clock += 30_000
  const blocked = await run()
  expect(blocked.fetchErrors).toHaveLength(0)
  expect(blocked.sessions).toHaveLength(0)
})

