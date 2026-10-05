import { describe, expect, test } from "bun:test"
import { mkdtemp, rm } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { Ledger } from "../src/ledger"
import { AttentionQueue, type RevalidationSources } from "../src/queue"
import { ConsoleChannel, type ConsoleClient } from "../src/console"
import { ClientError } from "../src/client"
import type { AttentionQueueItem, Message } from "../src/types"

const NOW = "2026-10-05T12:00:00.000Z"
const ROOT = "/root/ania"

class ThrowingClient implements ConsoleClient {
  readonly prompts: { sessionID: string; text: string }[] = []
  private counter = 0
  constructor(private readonly errorFactory: () => Error) {}

  async createSession(directory: string, _title: string): Promise<{ id: string; directory: string }> {
    this.counter += 1
    return { id: `ses_recreated_${this.counter}`, directory }
  }
  async promptAsync(sessionID: string, _directory: string, text: string): Promise<void> {
    this.prompts.push({ sessionID, text })
  }
  async listMessages(_sessionID: string, _directory: string, _limit?: number): Promise<readonly Message[]> {
    throw this.errorFactory()
  }
  async toast(_message: string, _title: string): Promise<void> {}
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

async function setup(errorFactory: () => Error) {
  const dir = await mkdtemp(join(tmpdir(), "supervisor-console-evict-"))
  const ledgerRef: { current: Ledger } = { current: await Ledger.open(join(dir, "ledger.jsonl")) }
  const queue = await AttentionQueue.open({
    path: join(dir, "queue.json"),
    append: async (type, payload) => { ledgerRef.current = await ledgerRef.current.append(type, payload) },
  })
  const client = new ThrowingClient(errorFactory)
  const channel = new ConsoleChannel({
    client,
    queue,
    statePath: join(dir, "consoles.json"),
    ledger: () => ledgerRef.current,
    setLedger: (next) => { ledgerRef.current = next },
    probe: async (_item: AttentionQueueItem) => healthyProbe(),
  })
  return { dir, queue, client, channel, ledgerRef }
}

async function seedConsole(channel: ConsoleChannel): Promise<string> {
  const id = await channel.ensure(ROOT, "[Supervisor] test")
  if (id === undefined) throw new Error("ensure failed in test seed")
  return id
}

describe("ConsoleChannel stale-console eviction", () => {
  test("404 on console poll evicts the console, its watermark, and logs CONSOLE_EVICTED", async () => {
    const harness = await setup(() => new ClientError("/session/ses_dead/message HTTP 404", { status: 404 }))
    const seeded = await seedConsole(harness.channel)
    expect(harness.channel.sessionID(ROOT)).toBe(seeded)
    const replies = await harness.channel.pollReplies(ROOT, NOW)
    expect(replies).toEqual([])
    expect(harness.channel.sessionID(ROOT)).toBeUndefined()
    const evicted = harness.ledgerRef.current.records.filter((record) => record.type === "CONSOLE_EVICTED")
    expect(evicted).toHaveLength(1)
    expect(evicted[0]?.payload).toEqual({ root: ROOT, sessionID: seeded, reason: "console session not found (HTTP 404)" })
    await rm(harness.dir, { recursive: true, force: true })
  })

  test("non-404 client errors propagate unchanged (no eviction)", async () => {
    const boom = new ClientError("/session/ses_x/message HTTP 503", { status: 503 })
    const harness = await setup(() => boom)
    const seeded = await seedConsole(harness.channel)
    let thrown: unknown
    try {
      await harness.channel.pollReplies(ROOT, NOW)
    } catch (error) {
      thrown = error
    }
    expect(thrown).toBe(boom)
    expect(harness.channel.sessionID(ROOT)).toBe(seeded)
    expect(harness.ledgerRef.current.records.filter((record) => record.type === "CONSOLE_EVICTED")).toEqual([])
    await rm(harness.dir, { recursive: true, force: true })
  })

  test("after eviction, ensure() re-creates a fresh console session", async () => {
    const harness = await setup(() => new ClientError("/session/ses_dead/message HTTP 404", { status: 404 }))
    await seedConsole(harness.channel)
    await harness.channel.pollReplies(ROOT, NOW)
    expect(harness.channel.sessionID(ROOT)).toBeUndefined()
    const recreated = await harness.channel.ensure(ROOT, "[Supervisor] test")
    expect(recreated).toBe("ses_recreated_2")
    await rm(harness.dir, { recursive: true, force: true })
  })
})
