import { describe, expect, test } from "bun:test"
import { mkdtemp, rm } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { Ledger } from "../src/ledger"
import { AttentionQueue, itemState, type RevalidationSources } from "../src/queue"
import {
  ConsoleChannel,
  correlateReply,
  glanceHeadline,
  parseDisposition,
  type ConsoleClient,
  type EscalationRequest,
  type ReplyEvent,
} from "../src/console"
import type { AttentionQueueItem, Message, QueueItemID } from "../src/types"

const NOW = "2026-09-20T12:00:00.000Z"

class StubClient implements ConsoleClient {
  readonly sessions: { id: string; directory: string }[] = []
  readonly messages = new Map<string, Message[]>()
  readonly prompts: { sessionID: string; text: string }[] = []
  readonly toasts: string[] = []
  private counter = 0

  async createSession(directory: string, title: string): Promise<{ id: string; directory: string }> {
    this.counter += 1
    const session = { id: `ses_console_${this.counter}`, directory }
    this.sessions.push(session)
    this.messages.set(session.id, [])
    return session
  }

  async promptAsync(sessionID: string, directory: string, text: string): Promise<void> {
    this.prompts.push({ sessionID, text })
    this.append(sessionID, "user", text)
  }

  async listMessages(sessionID: string): Promise<readonly Message[]> {
    return this.messages.get(sessionID) ?? []
  }

  async toast(message: string): Promise<void> {
    this.toasts.push(message)
  }

  append(sessionID: string, role: "user" | "assistant", text: string): void {
    const list = this.messages.get(sessionID) ?? []
    const id = `msg_${sessionID}_${list.length}`
    list.push({
      id,
      sessionID,
      role,
      time: { created: Date.now(), ...(role === "assistant" ? { completed: Date.now() } : {}) },
      parts: [{ id: `${id}_p`, messageID: id, type: "text", text }],
    })
    this.messages.set(sessionID, list)
  }
}

const healthyProbe = async (): Promise<RevalidationSources> => ({
  targetExists: () => true,
  targetIdle: () => true,
  latestMessageID: () => "msg-a1",
  targetTurnAborted: () => false,
  ticketOpen: () => true,
  blackboardFactActive: () => true,
  canonicalItemFor: () => undefined,
  answeredElsewhere: () => undefined,
  approvalRequired: () => false,
  modePermits: () => true,
  citationsAdmissible: () => true,
})

function escalationRequest(overrides: Partial<EscalationRequest> = {}): EscalationRequest {
  const base: EscalationRequest = {
    root: "/root",
    sessionID: "ses-a",
    question: "Deploy to prod?",
    rationale: "needs operator",
    citations: [],
    confidence: 0.9,
    target: { root: "/root", sessionID: "ses-a", userMessageID: "msg-u1", assistantMessageID: "msg-a1" },
  }
  return { ...base, ...overrides }
}

async function setup(probe: (item: AttentionQueueItem) => Promise<RevalidationSources> = healthyProbe) {
  const dir = await mkdtemp(join(tmpdir(), "supervisor-console-"))
  const ledgerRef: { current: Ledger } = { current: await Ledger.open(join(dir, "ledger.jsonl")) }
  const queue = await AttentionQueue.open({
    path: join(dir, "queue.json"),
    append: async (type, payload) => { ledgerRef.current = await ledgerRef.current.append(type, payload) },
  })
  const client = new StubClient()
  const channel = new ConsoleChannel({
    client,
    queue,
    statePath: join(dir, "consoles.json"),
    ledger: () => ledgerRef.current,
    setLedger: (next) => { ledgerRef.current = next },
    probe,
  })
  return { dir, queue, client, channel, ledgerRef }
}

const ledgerTypes = (ledgerRef: { current: Ledger }): readonly string[] => ledgerRef.current.records.map((record) => record.type)

describe("correlateReply", () => {
  const a: QueueItemID = "att_a"
  const b: QueueItemID = "att_b"
  const base = { root: "/root", unresolvedItemIDs: [a, b], resolveAlias: () => undefined }

  test("ambiguous when multiple unresolved items and none surfaced", () => {
    expect(correlateReply("deploy?", base)).toEqual({ status: "ambiguous", candidateItemIDs: [a, b] })
  })
  test("Q<n> prefix resolves through the alias map", () => {
    const context = { ...base, resolveAlias: (token: string) => (token === "Q1" ? a : undefined) }
    expect(correlateReply("Q1: deploy?", context)).toEqual({ status: "matched", itemID: a })
  })
  test("bare answer matches the single globally surfaced item", () => {
    expect(correlateReply("deploy?", { ...base, surfacedItemID: a, surfacedItemRoot: "/root" })).toEqual({ status: "matched", itemID: a })
  })
  test("bare answer does not match an item surfaced on another root", () => {
    expect(correlateReply("deploy?", { ...base, surfacedItemID: a, surfacedItemRoot: "/other-root" })).toEqual({ status: "ambiguous", candidateItemIDs: [a, b] })
  })
  test("bare answer matches the single unresolved item in the root", () => {
    expect(correlateReply("deploy?", { ...base, unresolvedItemIDs: [a] })).toEqual({ status: "matched", itemID: a })
  })
  test("unmatched when nothing is unresolved", () => {
    expect(correlateReply("deploy?", { ...base, unresolvedItemIDs: [] })).toEqual({ status: "unmatched" })
  })
  test("stable queue id resolves", () => {
    expect(correlateReply("att_b: yes", base)).toEqual({ status: "matched", itemID: b })
  })
  test("unknown Q<n> is unmatched, never guessed", () => {
    expect(correlateReply("Q9: yes", base)).toEqual({ status: "unmatched" })
  })
})

describe("parseDisposition", () => {
  test("recognizes skip/next/hold/dnd, with or without a ticket prefix", () => {
    expect(parseDisposition("skip")).toBe("SKIP")
    expect(parseDisposition("next")).toBe("SKIP")
    expect(parseDisposition("hold")).toBe("HOLD")
    expect(parseDisposition("dnd")).toBe("DND")
    expect(parseDisposition("Q1: skip")).toBe("SKIP")
    expect(parseDisposition("deploy?")).toBeUndefined()
  })
})

describe("glanceHeadline", () => {
  test("caps the headline at 60 characters", () => {
    expect(glanceHeadline("short").length).toBeLessThanOrEqual(60)
    expect(glanceHeadline("x".repeat(200)).length).toBeLessThanOrEqual(60)
  })
})

describe("ConsoleChannel dedupe", () => {
  test("duplicate escalations collapse to one queue item", async () => {
    const { channel, queue, dir } = await setup()
    const first = await channel.proposeEscalation(escalationRequest())
    const second = await channel.proposeEscalation(escalationRequest())
    if (first.kind === "capped" || second.kind === "capped") throw new Error("unexpected cap")
    expect(first.kind).toBe("enqueued")
    expect(second.item.id).toBe(first.item.id)
    expect(queue.items).toHaveLength(1)
    await rm(dir, { recursive: true, force: true })
  })
})

describe("ConsoleChannel lifecycle", () => {
  test("enqueue → revalidate → surface → correlate → propagation pending", async () => {
    const { channel, client, queue, ledgerRef, dir } = await setup()
    const proposed = await channel.proposeEscalation(escalationRequest())
    expect(proposed.kind).toBe("enqueued")

    const surfaced = await channel.surfaceNext("/root", NOW)
    expect(surfaced.kind).toBe("surfaced")
    if (surfaced.kind !== "surfaced") throw new Error("expected surface")
    expect(surfaced.alias).toBe("Q1")
    expect(client.prompts.some((prompt) => prompt.text.includes("[Supervisor] Q1 —"))).toBe(true)
    // Regression (2026-09-28 self-echo): the supervisor-authored ticket is a user
    // message in the console session — pollReplies must filter it, never route it.
    const ticketEcho = await channel.pollReplies("/root", NOW)
    expect(ticketEcho).toHaveLength(0)
    const consoleID = channel.sessionID("/root")
    if (consoleID === undefined) throw new Error("expected console session")
    client.append(consoleID, "user", "Q1: yes, deploy")

    const replies = await channel.pollReplies("/root", NOW)
    expect(replies).toHaveLength(1)
    const reply = replies[0]
    if (reply === undefined) throw new Error("expected reply")
    expect(reply.correlation).toEqual({ status: "matched", itemID: surfaced.item.id })

    const route = await channel.handleReply(reply, NOW)
    expect(route.kind).toBe("propagation-pending")
    const types = ledgerTypes(ledgerRef)
    expect(types).toContain("QUEUE_ITEM_PROPOSED")
    expect(types).toContain("QUEUE_ITEM_SURFACED")
    expect(types).toContain("QUEUE_REPLY_RECEIVED")
    expect(types).toContain("QUEUE_PROPAGATION_PROPOSED")
    expect(queue.items[0] === undefined ? undefined : itemState(queue.items[0])).toBe("answered")
    await rm(dir, { recursive: true, force: true })
  })

  test("answered-elsewhere retires the item", async () => {
    const evidence = { source: "session", sessionID: "ses-a", messageID: "msg-a2", digest: "d" } as const
    let answeredElsewhere = false
    const probe = async (): Promise<RevalidationSources> => ({ ...(await healthyProbe()), answeredElsewhere: () => (answeredElsewhere ? evidence : undefined) })
    const { channel, client, queue, ledgerRef, dir } = await setup(probe)
    await channel.proposeEscalation(escalationRequest())
    const surfaced = await channel.surfaceNext("/root", NOW)
    if (surfaced.kind !== "surfaced") throw new Error("expected surface")
    answeredElsewhere = true
    await channel.pollReplies("/root", NOW)
    await channel.pollReplies("/root", NOW)
    const consoleID = channel.sessionID("/root")
    if (consoleID === undefined) throw new Error("expected console session")
    client.append(consoleID, "user", "Q1: yes")
    const replies = await channel.pollReplies("/root", NOW)
    const reply = replies[0]
    if (reply === undefined) throw new Error("expected reply")
    const route = await channel.handleReply(reply, NOW)
    expect(route.kind).toBe("resolved")
    if (route.kind === "resolved") expect(route.disposition).toBe("retired-by-evidence")
    expect(ledgerTypes(ledgerRef)).toContain("QUEUE_ITEM_RESOLVED")
    expect(queue.items[0] === undefined ? undefined : itemState(queue.items[0])).toBe("resolved")
    await rm(dir, { recursive: true, force: true })
  })
})

describe("ConsoleChannel ambiguity", () => {
  test("ambiguous reply requests a numbered choice and resolves nothing", async () => {
    const { channel, client, queue, ledgerRef, dir } = await setup()
    await channel.proposeEscalation(escalationRequest())
    await channel.proposeEscalation(escalationRequest({
      sessionID: "ses-b",
      question: "Deploy B?",
      target: { root: "/root", sessionID: "ses-b", userMessageID: "msg-u2", assistantMessageID: "msg-a2" },
    }))
    await channel.ensure("/root", "[Supervisor] root")
    const consoleID = channel.sessionID("/root")
    if (consoleID === undefined) throw new Error("expected console session")
    await channel.pollReplies("/root", NOW)
    client.append(consoleID, "user", "yes")

    const replies = await channel.pollReplies("/root", NOW)
    const reply = replies[0]
    if (reply === undefined) throw new Error("expected reply")
    expect(reply.correlation.status).toBe("ambiguous")

    const route = await channel.handleReply(reply, NOW)
    expect(route.kind).toBe("ambiguous")
    expect(ledgerTypes(ledgerRef)).toContain("QUEUE_REPLY_AMBIGUOUS")
    expect(queue.items.every((item) => itemState(item) !== "resolved")).toBe(true)
    expect(client.prompts.some((prompt) => prompt.text.includes("Ambiguous reply"))).toBe(true)
    await rm(dir, { recursive: true, force: true })
  })
})

describe("ConsoleChannel dispositions", () => {
  test("SKIP snoozes the surfaced item for 30 minutes", async () => {
    const { channel, client, queue, dir } = await setup()
    await channel.proposeEscalation(escalationRequest())
    const surfaced = await channel.surfaceNext("/root", NOW)
    if (surfaced.kind !== "surfaced") throw new Error("expected surface")
    await channel.pollReplies("/root", NOW)
    const consoleID = channel.sessionID("/root")
    if (consoleID === undefined) throw new Error("expected console session")
    client.append(consoleID, "user", "Q1: skip")
    const replies = await channel.pollReplies("/root", NOW)
    const reply = replies[0]
    if (reply === undefined) throw new Error("expected reply")
    const route = await channel.handleReply(reply, NOW)
    expect(route.kind).toBe("disposition")
    if (route.kind === "disposition") expect(route.disposition).toBe("SKIP")
    const item = queue.items[0]
    if (item === undefined) throw new Error("expected item")
    expect(item.priority.notBefore).toBeDefined()
    expect(Date.parse(item.priority.notBefore ?? "")).toBeGreaterThan(Date.parse(NOW))
    await rm(dir, { recursive: true, force: true })
  })

  test("HOLD freezes surfacing on the channel", async () => {
    const { channel, client, dir } = await setup()
    await channel.proposeEscalation(escalationRequest())
    await channel.ensure("/root", "[Supervisor] root")
    const consoleID = channel.sessionID("/root")
    if (consoleID === undefined) throw new Error("expected console session")
    await channel.pollReplies("/root", NOW)
    client.append(consoleID, "user", "hold")
    const replies = await channel.pollReplies("/root", NOW)
    const reply = replies[0]
    if (reply === undefined) throw new Error("expected reply")
    const route = await channel.handleReply(reply, NOW)
    expect(route.kind).toBe("disposition")
    if (route.kind === "disposition") expect(route.disposition).toBe("HOLD")
    expect(channel.held?.root).toBe("/root")
    const next = await channel.surfaceNext("/root", NOW)
    expect(next.kind).toBe("suppressed")
    await rm(dir, { recursive: true, force: true })
  })

  test("DND freezes surfacing globally", async () => {
    const { channel, client, dir } = await setup()
    await channel.proposeEscalation(escalationRequest())
    await channel.ensure("/root", "[Supervisor] root")
    const consoleID = channel.sessionID("/root")
    if (consoleID === undefined) throw new Error("expected console session")
    await channel.pollReplies("/root", NOW)
    client.append(consoleID, "user", "dnd")
    const replies = await channel.pollReplies("/root", NOW)
    const reply = replies[0]
    if (reply === undefined) throw new Error("expected reply")
    const route = await channel.handleReply(reply, NOW)
    expect(route.kind).toBe("disposition")
    if (route.kind === "disposition") expect(route.disposition).toBe("DND")
    expect(channel.dnd).toBe(true)
    const next = await channel.surfaceNext("/root", NOW)
    expect(next.kind).toBe("suppressed")
    await rm(dir, { recursive: true, force: true })
  })

  test("resume clears the DND freeze", async () => {
    const { channel, client, dir } = await setup()
    await channel.proposeEscalation(escalationRequest())
    await channel.ensure("/root", "[Supervisor] root")
    const consoleID = channel.sessionID("/root")
    if (consoleID === undefined) throw new Error("expected console session")
    await channel.pollReplies("/root", NOW)
    client.append(consoleID, "user", "dnd")
    const dndReplies = await channel.pollReplies("/root", NOW)
    const dndReply = dndReplies[0]
    if (dndReply === undefined) throw new Error("expected reply")
    await channel.handleReply(dndReply, NOW)
    expect(channel.dnd).toBe(true)
    client.append(consoleID, "user", "resume")
    const resumeReplies = await channel.pollReplies("/root", NOW)
    const resumeReply = resumeReplies[0]
    if (resumeReply === undefined) throw new Error("expected reply")
    const route = await channel.handleReply(resumeReply, NOW)
    expect(route.kind).toBe("resumed")
    expect(channel.dnd).toBe(false)
    await rm(dir, { recursive: true, force: true })
  })
})

test("ticket and toast use human-oriented naming (title + project, not raw IDs)", async () => {
  const { formatTicket, glanceHeadline } = await import("../src/console")
  const item = {
    schemaVersion: 1, id: "att_1", version: 1, decisionKey: "k", kind: "decision",
    origin: { tickID: "tick_1", ledgerSeq: 1, decision: { action: "ESCALATE", rationale: "r", citations: [], confidence: 0.9 }, citations: [], informationNeeds: [], contextDigest: "" },
    target: { root: "/home/ezotoff/AI_projects/veran", sessionID: "ses_f3fb18cafffe", userMessageID: "u1", sessionTitle: "supervisor live queue cycle test" },
    actionClass: "ESCALATE", escalationKind: "DECISION", question: "Should the deploy proceed?",
    rationale: "r", priority: { stakes: 3, urgency: 3, confidence: 0.9, freshness: 1, createdAt: "t" },
    premises: [], relatedItemIDs: [], lifecycle: [], poisonCount: 0,
  } as never
  const ticket = formatTicket("Q2", item)
  expect(ticket).toContain("Q2 — supervisor live queue cycle test [veran]")
  expect(ticket).not.toContain("ses_f3fb18caff")
})

describe("stand-in ruling ingestion (assistant-role console turns)", () => {
  test("ingests a Q<n>:-marked assistant ruling, correlates it, never re-consumes it", async () => {
    const { channel, client, dir } = await setup()
    const proposed = await channel.proposeEscalation(escalationRequest())
    if (proposed.kind !== "enqueued") throw new Error("expected enqueue")
    const surfaced = await channel.surfaceNext("/root", NOW)
    if (surfaced.kind !== "surfaced") throw new Error("expected surface")
    expect(await channel.pollReplies("/root", NOW)).toHaveLength(0) // ticket echo filtered
    const consoleID = channel.sessionID("/root")
    if (consoleID === undefined) throw new Error("expected console session")
    // Stand-in chatter (no ruling marker) is ignored
    client.append(consoleID, "assistant", "Backlog numbering has advanced to BB-017.")
    // The ruling: markdown-bold Q<n> marker, as the console agent writes it
    client.append(consoleID, "assistant", "**Q1: DEFER the rerun to the operator — recommendation on record.**")
    const replies = await channel.pollReplies("/root", NOW)
    expect(replies).toHaveLength(1)
    const reply = replies[0]
    if (reply === undefined) throw new Error("expected reply")
    expect(reply.correlation).toEqual({ status: "matched", itemID: surfaced.item.id })
    expect(reply.normalizedText).toContain("DEFER the rerun")
    expect(reply.normalizedText.startsWith("Q1:")).toBe(false) // ticket prefix stripped
    // Watermark advanced past the ruling: not re-consumed
    expect(await channel.pollReplies("/root", NOW)).toHaveLength(0)
    await rm(dir, { recursive: true, force: true })
  })

  test("standInRuling normalizes the marker and rejects non-rulings", async () => {
    const { standInRuling } = await import("../src/console")
    expect(standInRuling("**Q4: DEFER to the operator.**")).toBe("Q4: DEFER to the operator.**")
    expect(standInRuling("Q7: skip the rerun")).toBe("Q7: skip the rerun")
    expect(standInRuling("Backlog numbering has advanced.")).toBeUndefined()
    expect(standInRuling("")).toBeUndefined()
  })
})

describe("pending propagation retry", () => {
  test("stuck answered item with stored reply is delivered on retry, then cleared", async () => {
    const deliveries: string[] = []
    const dir = await mkdtemp(join(tmpdir(), "supervisor-console-retry-"))
    const ledgerRef: { current: Ledger } = { current: await Ledger.open(join(dir, "ledger.jsonl")) }
    const queue = await AttentionQueue.open({
      path: join(dir, "queue.json"),
      append: async (type, payload) => { ledgerRef.current = await ledgerRef.current.append(type, payload) },
    })
    const client = new StubClient()
    const channel = new ConsoleChannel({
      client, queue, statePath: join(dir, "consoles.json"),
      ledger: () => ledgerRef.current, setLedger: (next) => { ledgerRef.current = next },
      probe: healthyProbe,
      deliverPropagation: async (input) => { deliveries.push(input.answer); return true },
    })
    const proposed = await channel.proposeEscalation(escalationRequest())
    if (proposed.kind !== "enqueued") throw new Error("expected enqueue")
    const surfaced = await channel.surfaceNext("/root", NOW)
    if (surfaced.kind !== "surfaced") throw new Error("expected surface")
    const consoleID = channel.sessionID("/root")
    if (consoleID === undefined) throw new Error("expected console session")
    expect(await channel.pollReplies("/root", NOW)).toHaveLength(0) // first poll seeds the watermark
    client.append(consoleID, "assistant", "**Q1: Approve option 2 and continue.**")
    const replies = await channel.pollReplies("/root", NOW)
    expect(replies).toHaveLength(1)
    const route = await channel.handleReply(replies[0]!, NOW)
    expect(route.kind).toBe("resolved")
    expect(deliveries).toEqual(["Approve option 2 and continue.**"])
    // Delivered answers are cleared: a later retry pass is a no-op.
    expect(await channel.retryPendingPropagations(NOW)).toBe(0)
    await rm(dir, { recursive: true, force: true })
  })

  test("recovered answered item without stored text never propagates a placeholder", async () => {
    const deliveries: string[] = []
    const dir = await mkdtemp(join(tmpdir(), "supervisor-console-recov-"))
    const ledgerRef: { current: Ledger } = { current: await Ledger.open(join(dir, "ledger.jsonl")) }
    const queue = await AttentionQueue.open({
      path: join(dir, "queue.json"),
      append: async (type, payload) => { ledgerRef.current = await ledgerRef.current.append(type, payload) },
    })
    const client = new StubClient()
    const channel = new ConsoleChannel({
      client, queue, statePath: join(dir, "consoles.json"),
      ledger: () => ledgerRef.current, setLedger: (next) => { ledgerRef.current = next },
      probe: healthyProbe,
      deliverPropagation: async (input) => { deliveries.push(input.answer); return true },
    })
    const proposed = await channel.proposeEscalation(escalationRequest())
    if (proposed.kind !== "enqueued") throw new Error("expected enqueue")
    // Simulate a pre-fix crash: item answered WITHOUT pendingAnswers persisted.
    await queue.markAnswered(proposed.item.id, "reply_lost", "console", NOW)
    const recovered = await channel.recoverAnswered()
    expect(recovered).toBe(1)
    expect(deliveries).toHaveLength(0) // no placeholder into worker sessions
    await rm(dir, { recursive: true, force: true })
  })
})
