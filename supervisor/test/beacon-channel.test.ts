import { describe, expect, test } from "bun:test"
import { mkdtemp, rm, writeFile } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { Ledger } from "../src/ledger"
import { AttentionQueue, type RevalidationSources } from "../src/queue"
import { ConsoleChannel, type ConsoleClient, type EscalationRequest } from "../src/console"
import { BeaconChannel, INBOX_TITLE_PREFIX, inboxTitle, parseEnvelope } from "../src/beacon"
import type { AttentionQueueItem, Message, Session } from "../src/types"

const NOW = "2026-09-26T12:00:00.000Z"

class StubClient implements ConsoleClient {
  readonly sessions: { id: string; directory: string; title?: string }[] = []
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

  async listSessions(directory: string): Promise<readonly Session[]> {
    return this.sessions
      .filter((session) => session.directory === directory)
      .map((session) => ({ id: session.id, directory: session.directory, ...(session.title === undefined ? {} : { title: session.title }) }))
  }

  async toast(message: string): Promise<void> {
    this.toasts.push(message)
  }

  /** Simulate the Beacon app creating its reply-inbox session (title convention). */
  addInbox(directory: string, title: string = inboxTitle(directory)): string {
    this.counter += 1
    const id = `ses_inbox_${this.counter}`
    this.sessions.push({ id, directory, title })
    this.messages.set(id, [])
    return id
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
  return {
    root: "/root",
    sessionID: "ses-a",
    question: "Deploy to prod?",
    rationale: "needs operator",
    citations: [],
    confidence: 0.9,
    target: { root: "/root", sessionID: "ses-a", userMessageID: "msg-u1", assistantMessageID: "msg-a1" },
    ...overrides,
  }
}

async function setup(probe: (item: AttentionQueueItem) => Promise<RevalidationSources> = healthyProbe) {
  const dir = await mkdtemp(join(tmpdir(), "supervisor-beacon-"))
  const ledgerRef: { current: Ledger } = { current: await Ledger.open(join(dir, "ledger.jsonl")) }
  const queue = await AttentionQueue.open({
    path: join(dir, "queue.json"),
    append: async (type, payload) => { ledgerRef.current = await ledgerRef.current.append(type, payload) },
  })
  const client = new StubClient()
  const consoles = new ConsoleChannel({
    client,
    queue,
    statePath: join(dir, "consoles.json"),
    ledger: () => ledgerRef.current,
    setLedger: (next) => { ledgerRef.current = next },
    probe,
  })
  const beacon = new BeaconChannel({
    client,
    queue,
    statePath: join(dir, "beacon.json"),
    aliases: () => consoles.aliasTable(),
    route: (reply, now) => consoles.handleReply(reply, now, { channelID: "beacon", promptChoice: false }),
  })
  return { dir, queue, client, consoles, beacon, ledgerRef }
}

const ledgerTypes = (ledgerRef: { current: Ledger }): readonly string[] => ledgerRef.current.records.map((record) => record.type)
const ledgerPayloads = (ledgerRef: { current: Ledger }, type: string): readonly Record<string, unknown>[] =>
  ledgerRef.current.records.filter((record) => record.type === type).map((record) => record.payload as Record<string, unknown>)

describe("parseEnvelope", () => {
  test("accepts a valid v1 envelope", () => {
    const envelope = parseEnvelope(JSON.stringify({ v: 1, clientMessageID: "c1", kind: "text", text: "use Qdrant", contextTag: "pres_x", explicitItemID: "att_1" }))
    expect(envelope).toEqual({ v: 1, clientMessageID: "c1", kind: "text", text: "use Qdrant", contextTag: "pres_x", explicitItemID: "att_1" })
  })
  test("rejects plain text, wrong version, missing kind, malformed JSON", () => {
    expect(parseEnvelope("Q1: yes")).toBeUndefined()
    expect(parseEnvelope(JSON.stringify({ v: 2, clientMessageID: "c", kind: "text" }))).toBeUndefined()
    expect(parseEnvelope(JSON.stringify({ v: 1, clientMessageID: "c" }))).toBeUndefined()
    expect(parseEnvelope("{not json}")).toBeUndefined()
    expect(parseEnvelope(JSON.stringify({ v: 1, clientMessageID: "c", kind: "choice", index: "zero" }))).toBeUndefined()
  })
})

describe("BeaconChannel polling", () => {
  test("no inbox session → no replies", async () => {
    const { beacon, dir } = await setup()
    expect(await beacon.poll("/root", NOW)).toEqual([])
    await rm(dir, { recursive: true, force: true })
  })

  test("first observation ingests the backlog: the reply that created the inbox is not swallowed", async () => {
    const { client, beacon, dir } = await setup()
    const inbox = client.addInbox("/root")
    client.append(inbox, "user", "Q1: yes")
    const replies = await beacon.poll("/root", NOW)
    expect(replies).toHaveLength(1)
    expect(replies[0]?.channelID).toBe("beacon")
    expect(await beacon.poll("/root", NOW)).toEqual([])
    await rm(dir, { recursive: true, force: true })
  })

  test("identical retransmits in the adoption backlog route once", async () => {
    const { client, consoles, beacon, dir } = await setup()
    const proposed = await consoles.proposeEscalation(escalationRequest())
    if (proposed.kind !== "enqueued") throw new Error("expected enqueue")
    const inbox = client.addInbox("/root")
    const envelope = JSON.stringify({ v: 1, clientMessageID: "cm-backlog", kind: "text", text: "yes", explicitItemID: proposed.item.id })
    client.append(inbox, "user", envelope)
    client.append(inbox, "user", envelope)
    expect(await beacon.poll("/root", NOW)).toHaveLength(1)
    await rm(dir, { recursive: true, force: true })
  })

  test("inbox binding is exact-title per root: a foreign title is never adopted", async () => {
    const { client, beacon, dir } = await setup()
    client.addInbox("/root", `${INBOX_TITLE_PREFIX}sub`)
    expect(await beacon.poll("/root", NOW)).toEqual([])
    expect(beacon.allSessionIDs().size).toBe(0)
    await rm(dir, { recursive: true, force: true })
  })

  test("explicitItemID envelope wins and routes through the shared reply-router", async () => {
    const { client, consoles, beacon, queue, ledgerRef, dir } = await setup()
    const proposed = await consoles.proposeEscalation(escalationRequest())
    if (proposed.kind !== "enqueued") throw new Error("expected enqueue")
    const inbox = client.addInbox("/root")
    client.append(inbox, "user", JSON.stringify({ v: 1, clientMessageID: "cm-1", kind: "text", text: "yes, deploy", explicitItemID: proposed.item.id }))
    const replies = await beacon.poll("/root", NOW)
    expect(replies).toHaveLength(1)
    const reply = replies[0]
    if (reply === undefined) throw new Error("expected reply")
    expect(reply.correlation).toEqual({ status: "matched", itemID: proposed.item.id })
    expect(reply.raw).toEqual({ kind: "text", text: "yes, deploy" })

    const route = await beacon.handleReply(reply, NOW)
    expect(route.kind).toBe("propagation-pending")
    const received = ledgerPayloads(ledgerRef, "QUEUE_REPLY_RECEIVED")
    expect(received.length).toBeGreaterThan(0)
    expect(received.every((payload) => payload["channelID"] === "beacon")).toBe(true)
    expect(ledgerTypes(ledgerRef)).toContain("QUEUE_PROPAGATION_PROPOSED")
    const item = queue.items[0]
    if (item === undefined) throw new Error("expected item")
    expect(item.lifecycle.at(-1)?.state).toBe("answered")
    await rm(dir, { recursive: true, force: true })
  })

  test("clientMessageID dedup: retransmitted envelope is dropped after routing", async () => {
    const { client, consoles, beacon, dir } = await setup()
    const proposed = await consoles.proposeEscalation(escalationRequest())
    if (proposed.kind !== "enqueued") throw new Error("expected enqueue")
    const inbox = client.addInbox("/root")
    const envelope = JSON.stringify({ v: 1, clientMessageID: "cm-dup", kind: "text", text: "yes", explicitItemID: proposed.item.id })
    client.append(inbox, "user", envelope)
    const replies = await beacon.poll("/root", NOW)
    expect(replies).toHaveLength(1)
    await beacon.handleReply(replies[0] ?? (() => { throw new Error("expected reply") })(), NOW)
    client.append(inbox, "user", envelope)
    expect(await beacon.poll("/root", NOW)).toHaveLength(0)
    await rm(dir, { recursive: true, force: true })
  })

  test("contextTag correlates to the currently surfaced presentation", async () => {
    const { client, consoles, beacon, dir } = await setup()
    await consoles.proposeEscalation(escalationRequest())
    const surfaced = await consoles.surfaceNext("/root", NOW)
    if (surfaced.kind !== "surfaced") throw new Error("expected surface")
    const inbox = client.addInbox("/root")
    client.append(inbox, "user", JSON.stringify({ v: 1, clientMessageID: "cm-ctx", kind: "choice", index: 1, contextTag: surfaced.presentationID }))
    const replies = await beacon.poll("/root", NOW)
    const reply = replies[0]
    if (reply === undefined) throw new Error("expected reply")
    expect(reply.correlation).toEqual({ status: "matched", itemID: surfaced.item.id })
    expect(reply.raw).toEqual({ kind: "choice", index: 1 })
    expect(reply.contextTag).toBe(surfaced.presentationID)
    await rm(dir, { recursive: true, force: true })
  })

  test("Q<n> alias resolves through the console alias table", async () => {
    const { client, consoles, beacon, dir } = await setup()
    await consoles.proposeEscalation(escalationRequest())
    const surfaced = await consoles.surfaceNext("/root", NOW)
    if (surfaced.kind !== "surfaced") throw new Error("expected surface")
    expect(surfaced.alias).toBe("Q1")
    const inbox = client.addInbox("/root")
    client.append(inbox, "user", "Q1: yes, ship it")
    const replies = await beacon.poll("/root", NOW)
    const reply = replies[0]
    if (reply === undefined) throw new Error("expected reply")
    expect(reply.correlation).toEqual({ status: "matched", itemID: surfaced.item.id })
    await rm(dir, { recursive: true, force: true })
  })

  test("ambiguous plain reply records QUEUE_REPLY_AMBIGUOUS and never prompts the console", async () => {
    const { client, consoles, beacon, queue, ledgerRef, dir } = await setup()
    await consoles.proposeEscalation(escalationRequest())
    await consoles.proposeEscalation(escalationRequest({
      sessionID: "ses-b",
      question: "Deploy B?",
      target: { root: "/root", sessionID: "ses-b", userMessageID: "msg-u2", assistantMessageID: "msg-a2" },
    }))
    const inbox = client.addInbox("/root")
    client.append(inbox, "user", "yes")
    const replies = await beacon.poll("/root", NOW)
    const reply = replies[0]
    if (reply === undefined) throw new Error("expected reply")
    expect(reply.correlation.status).toBe("ambiguous")
    await beacon.handleReply(reply, NOW)
    const ambiguous = ledgerPayloads(ledgerRef, "QUEUE_REPLY_AMBIGUOUS")
    expect(ambiguous.length).toBeGreaterThan(0)
    expect(ambiguous.every((payload) => payload["channelID"] === "beacon")).toBe(true)
    expect(queue.items.every((item) => item.lifecycle.at(-1)?.state !== "answered")).toBe(true)
    expect(client.prompts.some((prompt) => prompt.text.includes("Ambiguous reply"))).toBe(false)
    await rm(dir, { recursive: true, force: true })
  })

  test("inbox sessions are exposed for supervision exclusion", async () => {
    const { client, beacon, dir } = await setup()
    const inbox = client.addInbox("/root")
    await beacon.poll("/root", NOW)
    expect(beacon.allSessionIDs().has(inbox)).toBe(true)
    await rm(dir, { recursive: true, force: true })
  })

  test("v1 state migrates: loose bindings are dropped, processed IDs survive", async () => {
    const dir = await mkdtemp(join(tmpdir(), "supervisor-beacon-"))
    const ledgerRef: { current: Ledger } = { current: await Ledger.open(join(dir, "ledger.jsonl")) }
    const queue = await AttentionQueue.open({
      path: join(dir, "queue.json"),
      append: async (type, payload) => { ledgerRef.current = await ledgerRef.current.append(type, payload) },
    })
    const client = new StubClient()
    const consoles = new ConsoleChannel({
      client, queue,
      statePath: join(dir, "consoles.json"),
      ledger: () => ledgerRef.current,
      setLedger: (next) => { ledgerRef.current = next },
      probe: healthyProbe,
    })
    await writeFile(
      join(dir, "beacon.json"),
      JSON.stringify({ inboxes: { "/root": "ses_loose" }, watermarks: { ses_loose: "msg_x" }, processedClientMessageIDs: ["cm-old"] }),
    )
    const beacon = new BeaconChannel({
      client, queue,
      statePath: join(dir, "beacon.json"),
      aliases: () => consoles.aliasTable(),
      route: (reply, now) => consoles.handleReply(reply, now, { channelID: "beacon", promptChoice: false }),
    })
    await beacon.load()
    expect(beacon.allSessionIDs().size).toBe(0)
    const inbox = client.addInbox("/root")
    client.append(inbox, "user", JSON.stringify({ v: 1, clientMessageID: "cm-old", kind: "text", text: "hello" }))
    expect(await beacon.poll("/root", NOW)).toHaveLength(0)
    expect(beacon.allSessionIDs().has(inbox)).toBe(true)
    await rm(dir, { recursive: true, force: true })
  })

  test("state persists across reload (watermark + dedup survive restart)", async () => {
    const dir = await mkdtemp(join(tmpdir(), "supervisor-beacon-"))
    const ledgerRef: { current: Ledger } = { current: await Ledger.open(join(dir, "ledger.jsonl")) }
    const queue = await AttentionQueue.open({
      path: join(dir, "queue.json"),
      append: async (type, payload) => { ledgerRef.current = await ledgerRef.current.append(type, payload) },
    })
    const client = new StubClient()
    const consoles = new ConsoleChannel({
      client, queue,
      statePath: join(dir, "consoles.json"),
      ledger: () => ledgerRef.current,
      setLedger: (next) => { ledgerRef.current = next },
      probe: healthyProbe,
    })
    const makeBeacon = (): BeaconChannel => new BeaconChannel({
      client, queue,
      statePath: join(dir, "beacon.json"),
      aliases: () => consoles.aliasTable(),
      route: (reply, now) => consoles.handleReply(reply, now, { channelID: "beacon", promptChoice: false }),
    })
    const inbox = client.addInbox("/root")
    const first = makeBeacon()
    await first.load()
    client.append(inbox, "user", JSON.stringify({ v: 1, clientMessageID: "cm-persist", kind: "text", text: "hello" }))
    const persisted = await first.poll("/root", NOW)
    expect(persisted).toHaveLength(1)
    await first.handleReply(persisted[0] ?? (() => { throw new Error("expected reply") })(), NOW)

    const second = makeBeacon()
    await second.load()
    expect(await second.poll("/root", NOW)).toHaveLength(0)
    await rm(dir, { recursive: true, force: true })
  })
})

describe("crash-safe reply ingest (at-least-once)", () => {
  test("un-handled envelope is re-delivered on the next poll (crash between poll and route)", async () => {
    const { client, beacon, dir } = await setup()
    const inbox = client.addInbox("/root")
    client.append(inbox, "user", JSON.stringify({ v: 1, clientMessageID: "cm-a", kind: "text", text: "yes" }))
    const first = await beacon.poll("/root", NOW)
    expect(first).toHaveLength(1)
    expect(first[0]?.id).toBe("reply_cm-a")
    const second = await beacon.poll("/root", NOW)
    expect(second).toHaveLength(1)
    expect(second[0]?.id).toBe("reply_cm-a")
    await rm(dir, { recursive: true, force: true })
  })

  test("handled reply is promoted to processed and skipped on the next poll", async () => {
    const { client, beacon, dir } = await setup()
    const inbox = client.addInbox("/root")
    client.append(inbox, "user", JSON.stringify({ v: 1, clientMessageID: "cm-b", kind: "text", text: "yes" }))
    const replies = await beacon.poll("/root", NOW)
    expect(replies).toHaveLength(1)
    await beacon.handleReply(replies[0] ?? (() => { throw new Error("expected reply") })(), NOW)
    expect(await beacon.poll("/root", NOW)).toHaveLength(0)
    await rm(dir, { recursive: true, force: true })
  })

  test("crash simulation: pending survives a fresh BeaconChannel on the same statePath", async () => {
    const dir = await mkdtemp(join(tmpdir(), "supervisor-beacon-"))
    const ledgerRef: { current: Ledger } = { current: await Ledger.open(join(dir, "ledger.jsonl")) }
    const queue = await AttentionQueue.open({
      path: join(dir, "queue.json"),
      append: async (type, payload) => { ledgerRef.current = await ledgerRef.current.append(type, payload) },
    })
    const client = new StubClient()
    const consoles = new ConsoleChannel({
      client, queue,
      statePath: join(dir, "consoles.json"),
      ledger: () => ledgerRef.current,
      setLedger: (next) => { ledgerRef.current = next },
      probe: healthyProbe,
    })
    const makeBeacon = (): BeaconChannel => new BeaconChannel({
      client, queue,
      statePath: join(dir, "beacon.json"),
      aliases: () => consoles.aliasTable(),
      route: (reply, now) => consoles.handleReply(reply, now, { channelID: "beacon", promptChoice: false }),
    })
    const inbox = client.addInbox("/root")
    client.append(inbox, "user", JSON.stringify({ v: 1, clientMessageID: "cm-c", kind: "text", text: "yes" }))
    const crashed = makeBeacon()
    await crashed.load()
    expect(await crashed.poll("/root", NOW)).toHaveLength(1)
    // crash: no handleReply — a new channel takes over the same durable state
    const revived = makeBeacon()
    await revived.load()
    const replies = await revived.poll("/root", NOW)
    expect(replies).toHaveLength(1)
    expect(replies[0]?.id).toBe("reply_cm-c")
    await rm(dir, { recursive: true, force: true })
  })

  test("pending message behind an advanced watermark is still re-ingested", async () => {
    const { client, beacon, dir } = await setup()
    const inbox = client.addInbox("/root")
    client.append(inbox, "user", JSON.stringify({ v: 1, clientMessageID: "cm-d", kind: "text", text: "yes" }))
    expect(await beacon.poll("/root", NOW)).toHaveLength(1)
    // a later non-envelope message advances the watermark past the pending one
    client.append(inbox, "user", "plain note")
    const second = await beacon.poll("/root", NOW)
    expect(second.map((reply) => reply.id)).toContain("reply_cm-d")
    expect(second.some((reply) => reply.normalizedText === "plain note")).toBe(true)
    await rm(dir, { recursive: true, force: true })
  })

  test("route throw leaves it pending; later success promotes and skips", async () => {
    const dir = await mkdtemp(join(tmpdir(), "supervisor-beacon-"))
    const ledgerRef: { current: Ledger } = { current: await Ledger.open(join(dir, "ledger.jsonl")) }
    const queue = await AttentionQueue.open({
      path: join(dir, "queue.json"),
      append: async (type, payload) => { ledgerRef.current = await ledgerRef.current.append(type, payload) },
    })
    const client = new StubClient()
    const consoles = new ConsoleChannel({
      client, queue,
      statePath: join(dir, "consoles.json"),
      ledger: () => ledgerRef.current,
      setLedger: (next) => { ledgerRef.current = next },
      probe: healthyProbe,
    })
    let failing = true
    const beacon = new BeaconChannel({
      client, queue,
      statePath: join(dir, "beacon.json"),
      aliases: () => consoles.aliasTable(),
      route: async (reply, now, options) => {
        if (failing) throw new Error("route crashed")
        return consoles.handleReply(reply, now, options)
      },
    })
    const inbox = client.addInbox("/root")
    client.append(inbox, "user", JSON.stringify({ v: 1, clientMessageID: "cm-e", kind: "text", text: "yes" }))
    const replies = await beacon.poll("/root", NOW)
    expect(replies).toHaveLength(1)
    const reply = replies[0] ?? (() => { throw new Error("expected reply") })()
    await expect(beacon.handleReply(reply, NOW)).rejects.toThrow("route crashed")
    // still pending → re-delivered, then a successful route promotes it
    const redelivered = await beacon.poll("/root", NOW)
    expect(redelivered).toHaveLength(1)
    failing = false
    await beacon.handleReply(redelivered[0] ?? (() => { throw new Error("expected reply") })(), NOW)
    expect(await beacon.poll("/root", NOW)).toHaveLength(0)
    await rm(dir, { recursive: true, force: true })
  })
})

describe("inbox title convention", () => {
  test("prefix must not collide with the supervisor console prefix", () => {
    expect(INBOX_TITLE_PREFIX.startsWith("[Supervisor]")).toBe(false)
    expect(inboxTitle("/home/ezotoff/AI_projects/veran")).toBe("[Beacon replies] veran")
    expect(inboxTitle("/home/ezotoff/AI_projects/veran/apps/web")).toBe("[Beacon replies] web")
  })
})
