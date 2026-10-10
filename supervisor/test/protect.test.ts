import { describe, expect, test } from "bun:test"
import { mkdtemp } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { ProtectionRegistry } from "../src/protect"
import { AttentionQueue } from "../src/queue"
import { pickTarget } from "../src/targets"
import type { Message, Part, Turn } from "../src/types"
import type { LedgerAppend, ProposeInput } from "../src/queue"
import type { LedgerRecordType } from "../src/types"

const part = (text?: string): Part => ({ id: "p", messageID: "m", type: "text", ...(text === undefined ? {} : { text }) })
const message = (id: string, role: "user" | "assistant", fields: { text?: string; completed?: number } = {}): Message => ({
  id,
  sessionID: "ses-a",
  role,
  time: { created: 1, ...(fields.completed === undefined ? {} : { completed: fields.completed }) },
  parts: fields.text === undefined ? [] : [part(fields.text)],
})
const turn = (userMessageID: string, assistantMessageID: string): Turn => ({
  sessionID: "ses-a",
  userMessageID,
  assistantMessageID,
  origin: "human",
  userText: "continue",
  assistantText: "working",
  transcript: "t",
})
const idleKickStartFixture = (): { turns: Turn[]; messages: Message[] } => ({
  turns: [turn("u1", "a1")],
  messages: [message("u1", "user", { text: "continue" }), message("a1", "assistant", { text: "stalled", completed: 2 })],
})

const proposeInput = (sessionID: string, actionClass: "CONTINUE" | "ESCALATE"): ProposeInput => ({
  kind: "decision",
  origin: {
    tickID: "tick_protect",
    ledgerSeq: 0,
    decision: { action: actionClass, rationale: "r", citations: [], confidence: 0.9 },
    citations: [],
    informationNeeds: [],
    contextDigest: "d",
  },
  target: { root: "/root", sessionID, userMessageID: "u1", assistantMessageID: "a1" },
  actionClass,
  ...(actionClass === "ESCALATE" ? { escalationKind: "DECISION" as const } : {}),
  question: "kick the stalled session?",
  rationale: "stalled",
  priority: { stakes: 3, urgency: 3, confidence: 0.9, freshness: 1, createdAt: new Date().toISOString() },
  premises: [],
})

const collectAppends = (): { appended: Array<{ type: LedgerRecordType; payload: unknown }>; append: LedgerAppend } => {
  const appended: Array<{ type: LedgerRecordType; payload: unknown }> = []
  const append = async (type: LedgerRecordType, payload: unknown): Promise<void> => {
    appended.push({ type, payload })
  }
  return { appended, append }
}

async function registryPath(): Promise<string> {
  const directory = await mkdtemp(join(tmpdir(), "protect-test-"))
  return join(directory, "protected.json")
}

describe("ProtectionRegistry", () => {
  test("protect then isProtected; unprotect restores; unprotect of unknown is false", async () => {
    const path = await registryPath()
    const registry = await ProtectionRegistry.open(path)
    expect(registry.isProtected("ses-a")).toBe(false)
    await registry.protect("ses-a", { reason: "stopped deliberately" })
    expect(registry.isProtected("ses-a")).toBe(true)
    const removed = await registry.unprotect("ses-a")
    expect(removed).toBe(true)
    expect(registry.isProtected("ses-a")).toBe(false)
    expect(await registry.unprotect("ses-a")).toBe(false)
  })

  test("append-only change log records every protect/unprotect", async () => {
    const path = await registryPath()
    const registry = await ProtectionRegistry.open(path)
    await registry.protect("ses-a", { reason: "operator stopped it" })
    await registry.unprotect("ses-a")
    expect(registry.history.map((change) => change.action)).toEqual(["protect", "unprotect"])
    expect(registry.history[0]?.reason).toBe("operator stopped it")
  })

  test("registry persists across restart (reload from disk)", async () => {
    const path = await registryPath()
    const first = await ProtectionRegistry.open(path)
    await first.protect("ses-a", { reason: "keep" })
    const second = await ProtectionRegistry.open(path)
    expect(second.isProtected("ses-a")).toBe(true)
    expect(second.entries[0]?.reason).toBe("keep")
  })

  test("protect is idempotent and keeps the original entry", async () => {
    const path = await registryPath()
    const registry = await ProtectionRegistry.open(path)
    const first = await registry.protect("ses-a", { reason: "one" })
    const again = await registry.protect("ses-a", { reason: "two" })
    expect(again).toBe(first)
    expect(registry.history).toHaveLength(1)
  })
})

describe("pickTarget protection gate", () => {
  test("protected session is never a CONTINUE target; unprotect restores eligibility", () => {
    const { turns, messages } = idleKickStartFixture()
    const target = pickTarget(turns, messages)
    expect(target).toHaveProperty("target")
    expect(pickTarget(turns, messages, { sessionProtected: true })).toMatchObject({ rejected: "protected" })
    expect(pickTarget(turns, messages, { sessionProtected: false })).toHaveProperty("target")
  })

  test("gate composes with the abort guard (aborted + protected → undefined)", () => {
    const aborted = idleKickStartFixture()
    const user = aborted.messages[0]
    const assistant = aborted.messages[1]
    if (user === undefined || assistant === undefined) throw new Error("fixture must have two messages")
    const withAbort = { turns: aborted.turns, messages: [user, { ...assistant, finish: "aborted" }] }
    expect(pickTarget(withAbort.turns, withAbort.messages)).toMatchObject({ rejected: "aborted" })
    expect(pickTarget(withAbort.turns, withAbort.messages, { sessionProtected: true })).toMatchObject({ rejected: "protected" })
  })
})

describe("queue protection gate", () => {
  test("service predicate skips protected CONTINUE targets while preserving ESCALATE", async () => {
    const path = await registryPath()
    const registry = await ProtectionRegistry.open(path)
    await registry.protect("ses-a")
    const protectedSession = (sessionID: string): boolean => registry.isProtected(sessionID)
    const { turns, messages } = idleKickStartFixture()
    const { append } = collectAppends()
    const queue = await AttentionQueue.open({ path: join(path, "..", "queue.json"), append, protectedSession })

    expect(pickTarget(turns, messages, { sessionProtected: protectedSession("ses-a") })).toMatchObject({ rejected: "protected" })
    expect((await queue.propose(proposeInput("ses-a", "ESCALATE"))).kind).toBe("created")
  })

  test("CONTINUE proposal for a protected session is blocked; ESCALATE still proposes", async () => {
    const path = await registryPath()
    const registry = await ProtectionRegistry.open(path)
    await registry.protect("ses-a")
    const { appended, append } = collectAppends()
    const queue = await AttentionQueue.open({ path: join(path, "..", "queue.json"), append, protectedSession: (sessionID) => registry.isProtected(sessionID) })

    const blocked = await queue.propose(proposeInput("ses-a", "CONTINUE"))
    expect(blocked.kind).toBe("blocked")

    const escalate = await queue.propose(proposeInput("ses-a", "ESCALATE"))
    expect(escalate.kind).toBe("created")
    expect(appended.some((record) => record.type === "QUEUE_ITEM_PROPOSED")).toBe(true)
    expect(appended.some((record) => record.type === "QUEUE_PROPOSAL_DEDUPED")).toBe(true)
  })

  test("unprotect restores CONTINUE proposals", async () => {
    const path = await registryPath()
    const registry = await ProtectionRegistry.open(path)
    await registry.protect("ses-a")
    const { append } = collectAppends()
    const queuePath = join(path, "..", "queue.json")
    const queue = await AttentionQueue.open({ path: queuePath, append, protectedSession: (sessionID) => registry.isProtected(sessionID) })
    expect((await queue.propose(proposeInput("ses-a", "CONTINUE"))).kind).toBe("blocked")
    await registry.unprotect("ses-a")
    expect((await queue.propose(proposeInput("ses-a", "CONTINUE"))).kind).toBe("created")
  })

  test("CONTINUE for an unprotected session passes untouched", async () => {
    const path = await registryPath()
    const registry = await ProtectionRegistry.open(path)
    const { append } = collectAppends()
    const queue = await AttentionQueue.open({ path: join(path, "..", "queue.json"), append, protectedSession: (sessionID) => registry.isProtected(sessionID) })
    expect((await queue.propose(proposeInput("ses-a", "CONTINUE"))).kind).toBe("created")
  })
})
