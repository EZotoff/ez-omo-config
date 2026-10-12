import { describe, expect, test } from "bun:test"
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { Ledger } from "../src/ledger"
import { AttentionQueue, itemState, type RevalidationSources } from "../src/queue"
import { ConsoleChannel, type ConsoleClient, type EscalationRequest } from "../src/console"
import type { AttentionQueueItem, Message } from "../src/types"

const NOW = "2026-10-12T12:00:00.000Z"

class StubClient implements ConsoleClient {
  readonly messages = new Map<string, Message[]>()
  readonly prompts: { sessionID: string; text: string }[] = []
  async createSession(directory: string): Promise<{ id: string; directory: string }> {
    const id = `ses_${directory.replaceAll("/", "_")}`
    this.messages.set(id, [])
    return { id, directory }
  }
  async promptAsync(sessionID: string, _directory: string, text: string): Promise<void> {
    this.prompts.push({ sessionID, text })
  }
  async listMessages(sessionID: string): Promise<readonly Message[]> {
    return this.messages.get(sessionID) ?? []
  }
  async toast(): Promise<void> {}
}

const validProbe = async (): Promise<RevalidationSources> => ({
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

const redecideProbe = async (): Promise<RevalidationSources> => ({
  ...(await validProbe()),
  latestMessageID: () => "msg-new",
})

function escalationRequest(): EscalationRequest {
  return {
    root: "/root",
    sessionID: "ses-a",
    question: "Deploy to prod?",
    rationale: "needs operator",
    citations: [],
    confidence: 0.9,
    target: { root: "/root", sessionID: "ses-a", userMessageID: "msg-u1", assistantMessageID: "msg-a1" },
  }
}

type Harness = {
  readonly dir: string
  readonly queue: AttentionQueue
  readonly client: StubClient
  readonly channel: ConsoleChannel
  readonly ledgerRef: { current: Ledger }
}

async function harness(
  probe: (item: AttentionQueueItem) => Promise<RevalidationSources> = validProbe,
  onRedecide?: (item: AttentionQueueItem) => void,
): Promise<Harness> {
  const dir = await mkdtemp(join(tmpdir(), "supervisor-bri-"))
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
    ...(onRedecide === undefined ? {} : { onRedecide }),
  })
  return { dir, queue, client, channel, ledgerRef }
}

async function proposedItem(h: Harness): Promise<string> {
  const result = await h.channel.proposeEscalation(escalationRequest())
  if (result.kind === "capped") throw new Error("unexpected cap")
  return result.item.id
}

const receipts = (ledgerRef: { current: Ledger }) =>
  ledgerRef.current.records.filter((record) => record.type === "QUEUE_REPLY_RECEIVED")

describe("recovered-reply integrity (beacon-reply-integrity)", () => {
  test("retry preserves the original channelID and replyEventID of a structured outbox entry", async () => {
    // Given: a beacon-originated answer persisted in the outbox, with the item
    // never marked answered (crash window between persist and markAnswered).
    const h = await harness()
    try {
      const itemID = await proposedItem(h)
      await writeFile(join(h.dir, "consoles.json"), JSON.stringify({
        pendingAnswers: { [itemID]: { text: "prepare the packager", replyEventID: "reply_beacon_1", channelID: "beacon" } },
      }))
      const deliveries: string[] = []
      const retrying = new ConsoleChannel({
        client: h.client, queue: h.queue, statePath: join(h.dir, "consoles.json"),
        ledger: () => h.ledgerRef.current, setLedger: (next) => { h.ledgerRef.current = next },
        probe: validProbe,
        deliverPropagation: async ({ answer }) => { deliveries.push(answer); return true },
      })
      await retrying.load()
      // When
      await retrying.retryPendingPropagations("/root", NOW)
      // Then: delivered under the ORIGINAL reply identity — not console/recovered_
      expect(deliveries).toEqual(["prepare the packager"])
      const final = h.queue.items.find((item) => item.id === itemID)
      if (final === undefined) throw new Error("missing item")
      expect(itemState(final)).toBe("resolved")
      const recorded = receipts(h.ledgerRef)
      expect(recorded).toHaveLength(1)
      expect(recorded[0]?.payload).toMatchObject({ itemID, replyEventID: "reply_beacon_1", channelID: "beacon" })
    } finally { await rm(h.dir, { recursive: true, force: true }) }
  })

  test("legacy string outbox entries fall back to console/recovered_ identity", async () => {
    const h = await harness()
    try {
      const itemID = await proposedItem(h)
      await writeFile(join(h.dir, "consoles.json"), JSON.stringify({ pendingAnswers: { [itemID]: "legacy answer" } }))
      const retrying = new ConsoleChannel({
        client: h.client, queue: h.queue, statePath: join(h.dir, "consoles.json"),
        ledger: () => h.ledgerRef.current, setLedger: (next) => { h.ledgerRef.current = next },
        probe: validProbe,
        deliverPropagation: async () => true,
      })
      await retrying.load()
      await retrying.retryPendingPropagations("/root", NOW)
      expect(receipts(h.ledgerRef)).toHaveLength(1)
      expect(receipts(h.ledgerRef)[0]?.payload).toMatchObject({ itemID, replyEventID: `recovered_${itemID}`, channelID: "console" })
    } finally { await rm(h.dir, { recursive: true, force: true }) }
  })
})
