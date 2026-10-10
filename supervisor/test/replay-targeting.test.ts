import { afterEach, expect, test } from "bun:test"
import { mkdtemp, rm } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { targetingReplays } from "./fixtures/targeting-replays"
import { pickTarget } from "../src/targets"
import { projectTurns } from "../src/projector"
import { runTickWithCollect } from "../src/tick"
import { applyAttentionOverrides, SessionScheduler } from "../src/service"
import { ConsoleChannel, type ConsoleClient } from "../src/console"
import { AttentionQueue, type RevalidationSources } from "../src/queue"
import { Ledger } from "../src/ledger"
import { PendingAttentionStore } from "../src/pending"
import type { Message } from "../src/types"

const directories: string[] = []
afterEach(async () => { await Promise.all(directories.splice(0).map((path) => rm(path, { recursive: true, force: true }))) })
const registry = { humanMessageIDs: new Set<string>(), supervisorMessageIDs: new Set<string>() }
function exchange(sessionID: string, reply: string, suffix = "1", synthetic = true): readonly Message[] {
  return [
    { id: `u${suffix}`, sessionID, role: "user", time: { created: 1 }, parts: [{ id: `pu${suffix}`, messageID: `u${suffix}`, type: "text", text: "[supervisor] continue", synthetic }] },
    { id: `a${suffix}`, sessionID, role: "assistant", time: { created: 2, completed: 3 }, parts: [{ id: `pa${suffix}`, messageID: `a${suffix}`, type: "text", text: reply }] },
  ]
}

async function harness(root: string, sessionID: string) {
  const directory = await mkdtemp(join(tmpdir(), "supervisor-targeting-replay-"))
  directories.push(directory)
  let ledger = await Ledger.open(join(directory, "ledger.jsonl"))
  const queue = await AttentionQueue.open({ path: join(directory, "queue.json"), append: async (type, payload) => { ledger = await ledger.append(type, payload) } })
  let messages: readonly Message[] = []
  let judgeCalls = 0
  const reticks: string[] = []
  const delivered: string[] = []
  const client: ConsoleClient = {
    createSession: async (directory) => ({ id: "console", directory }),
    listMessages: async () => [],
    promptAsync: async (_sessionID, _directory, text) => { delivered.push(text) },
    toast: async () => undefined,
  }
  const probe = async (): Promise<RevalidationSources> => ({
    targetExists: () => true, targetIdle: () => true, latestMessageID: () => messages.at(-1)?.id,
    targetTurnAborted: () => false, ticketOpen: () => true, blackboardFactActive: () => true,
    canonicalItemFor: () => undefined, answeredElsewhere: () => undefined, approvalRequired: () => false,
    modePermits: () => true, citationsAdmissible: () => true,
  })
  const channel = new ConsoleChannel({ client, queue, statePath: join(directory, "consoles.json"), ledger: () => ledger, setLedger: (next) => { ledger = next }, probe, onRedecide: (item) => { reticks.push(item.target.sessionID) } })
  await channel.ensure(root, "[Supervisor] replay")
  delivered.splice(0)
  const tick = async (canned: Readonly<Record<string, unknown>>) => {
    const turns = projectTurns(messages, registry, { adjudicateMachineOrigin: true })
    const selection = pickTarget(turns, messages, {
      adjudicateMachineOrigin: true,
      escalatedAssistantMessageIDs: queue.items.flatMap((item) => item.target.assistantMessageID === undefined ? [] : [item.target.assistantMessageID]),
    })
    if ("rejected" in selection) return selection
    const target = selection.target
    const judged = await runTickWithCollect({
      adapter: { complete: async () => { judgeCalls += 1; return JSON.stringify(canned) } },
      context: { text: target.transcript, estimatedTokens: 100, truncated: false }, target, confidenceFloor: 0.6,
      root, executor: { run: async () => { throw new Error("unexpected collect") } },
      budget: { allow: () => false, record: () => undefined }, isIdle: async () => true,
      healthAmbiguous: false, hasSiblings: false, nowMs: () => 0,
    })
    const decision = await applyAttentionOverrides(judged, { adjudicateMachineOrigin: true, verifyWake: true, wakeVerifier: async () => false })
    ledger = await ledger.append("TICK_DECIDED", { root, sessionID, decision })
    if (decision.action === "ESCALATE") {
      await channel.proposeEscalation({ root, sessionID, question: decision.rationale, rationale: "replay evidence", confidence: decision.confidence, citations: decision.citations, target: { root, sessionID, userMessageID: target.userMessageID, ...(target.assistantMessageID === undefined ? {} : { assistantMessageID: target.assistantMessageID }) } })
      await channel.surfaceNext(root, "2026-10-10T12:00:00.000Z")
    }
    return decision
  }
  return { directory, queue, channel, reticks, delivered, tick, setMessages: (next: readonly Message[]) => { messages = next }, judgeCalls: () => judgeCalls }
}

for (const fixture of targetingReplays) test(`ledger seq ${fixture.seq} replays through canned judge to an operator ticket`, async () => {
  const h = await harness(fixture.root, fixture.sessionID)
  h.setMessages(exchange(fixture.sessionID, fixture.reply, "1", fixture.synthetic))
  const decision = await h.tick({ action: fixture.action, rationale: fixture.reply, confidence: 0.9, citations: [], operator_input_requested: fixture.operatorInputRequested, wake_handle: "wakeHandle" in fixture ? fixture.wakeHandle : null })
  expect(decision).toMatchObject({ action: "ESCALATE" })
  expect(h.queue.items).toHaveLength(1)
  expect(h.delivered).toHaveLength(1)
  expect(h.judgeCalls()).toBe(1)
})

test("ESCALATE → re-decide → ESCALATE consumes a newer assistant only", async () => {
  const h = await harness("/project", "s")
  const canned = { action: "ACCEPT", rationale: "Which way?", citations: [], confidence: 0.9, operator_input_requested: true }
  h.setMessages(exchange("s", "Which way?"))
  await h.tick(canned)
  const first = h.queue.items[0]
  if (first === undefined) throw new Error("missing first escalation")
  h.setMessages([...exchange("s", "Which way?"), ...exchange("s", "Choose the next step", "2")])
  await h.channel.handleReply({ schemaVersion: 1, id: "reply_cycle", root: "/project", receivedAt: "2026-10-10T12:00:00.000Z", channelID: "console", raw: { kind: "text", text: "A" }, normalizedText: "A", correlation: { status: "matched", itemID: first.id } }, "2026-10-10T12:00:00.000Z")
  expect(h.reticks).toEqual(["s"])
  await h.tick({ ...canned, rationale: "Choose the next step" })
  expect(await h.tick(canned)).toMatchObject({ rejected: "stale-target" })
  expect(h.queue.items.map((item) => item.target.assistantMessageID)).toEqual(["a1", "a2"])
  expect(h.judgeCalls()).toBe(2)
})

test("a durable missing-context skip retries using a fresh turn without a new poll edge", async () => {
  const h = await harness("/project", "s")
  const clock = { now: 0 }
  const pending = await PendingAttentionStore.open({ path: join(h.directory, "pending.json"), now: () => clock.now, maxAttempts: 4, backoffS: [120, 300, 900, 1800] })
  await pending.record({ root: "/project", sessionID: "s", reason: "missing-context" })
  const restarted = await PendingAttentionStore.open({ path: join(h.directory, "pending.json"), now: () => clock.now, maxAttempts: 4, backoffS: [120, 300, 900, 1800] })
  clock.now = 120_000
  h.setMessages(exchange("s", "Say A/B/C.", "fresh"))
  const scheduler = new SessionScheduler(300_000, () => clock.now, async () => {
    await h.tick({ action: "ACCEPT", rationale: "Say A/B/C.", citations: [], confidence: 0.9, operator_input_requested: true })
    await restarted.resolve({ root: "/project", sessionID: "s" })
    scheduler.markTicked("s")
  })
  for (const record of restarted.due()) await scheduler.enqueueRetry(record.sessionID, async () => { await restarted.beginAttempt(record); return true })
  expect(h.queue.items[0]?.target.assistantMessageID).toBe("afresh")
  expect(restarted.records[0]).toMatchObject({ disposition: "resolved", attempts: 1 })
})
