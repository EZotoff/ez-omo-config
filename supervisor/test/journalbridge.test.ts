import { afterEach, describe, expect, test } from "bun:test"
import { mkdtemp, rm } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { Ledger } from "../src/ledger"
import { ContinuationBridge, decodeJournalJson, parseContinuationAlert, type JournalEntry } from "../src/journalbridge"

const paths: string[] = []
afterEach(async () => Promise.all(paths.splice(0).map((path) => rm(path, { recursive: true, force: true }))))

const mk = (cursor: string, message: string): JournalEntry => ({ cursor, message })

function entry(reason: string, uuid: string, unit = "opencode-interactive.service"): JournalEntry {
  return mk(`cursor-${reason}-${uuid}`, `restart-continuation: test alert unit=${unit} reason=${reason} rc=- uuid=${uuid} count=2 ts=1695000000`)
}

async function openBridge(directory: string, entries: JournalEntry[]): Promise<{ bridge: ContinuationBridge; ledgerPath: string }> {
  const ledgerPath = join(directory, "ledger.jsonl")
  await Ledger.open(ledgerPath)
  const bridge = new ContinuationBridge({
    statePath: join(directory, "journal-bridge.json"),
    read: async (afterCursor) => {
      if (afterCursor === undefined) return entries
      const index = entries.findIndex((e) => e.cursor === afterCursor)
      return index === -1 ? [] : entries.slice(index + 1)
    },
    append: async (type, payload) => {
      const ledger = await Ledger.open(ledgerPath)
      await ledger.append(type, payload)
    },
  })
  return { bridge, ledgerPath }
}

async function continuationRows(path: string): Promise<{ decision: { action: string; confidence: number }; continuation: Record<string, string> }[]> {
  const ledger = await Ledger.open(path)
  return ledger.records
    .filter((record) => record.type === "TICK_DECIDED")
    .map((record) => record.payload as { decision: { action: string; confidence: number }; continuation: Record<string, string> })
}

describe("parseContinuationAlert", () => {
  test("parses the suffix contract and rejects foreign reasons", () => {
    const alert = parseContinuationAlert("restart-continuation: crash-class resume from checkpoint u1 for opencode.service: 3 sessions re-prompted unit=opencode.service reason=resume_fallback rc=- uuid=u1 count=3 ts=1695000000")
    expect(alert?.unit).toBe("opencode.service")
    expect(alert?.reason).toBe("resume_fallback")
    expect(alert?.rc).toBe("-")
    expect(alert?.uuid).toBe("u1")
    expect(alert?.count).toBe("3")
    expect(alert?.ts).toBe("1695000000")
    expect(alert?.fingerprint).toHaveLength(64)
    expect(parseContinuationAlert("no suffix here")).toBeUndefined()
    expect(parseContinuationAlert("x unit=a reason=other_reason rc=- uuid=b count=1 ts=2")).toBeUndefined()
  })

  test("decodeJournalJson handles newline-separated and concatenated objects", () => {
    const a = JSON.stringify({ __CURSOR: "c1", MESSAGE: "m1" })
    const b = JSON.stringify({ __CURSOR: "c2", MESSAGE: "m2 { not json" })
    expect(decodeJournalJson(`${a}\n${b}`)).toEqual([{ cursor: "c1", message: "m1" }, { cursor: "c2", message: "m2 { not json" }])
    expect(decodeJournalJson(`${a}${b}`)).toHaveLength(2)
  })
})

describe("ContinuationBridge", () => {
  test("QA scenario 1: each reason imports exactly one ESCALATE row with expected fields", async () => {
    const directory = await mkdtemp(join(tmpdir(), "supervisor-bridge-")); paths.push(directory)
    const reasons = ["preflight_failed", "snapshot_failed", "resume_fallback", "db_fallback"]
    const { bridge, ledgerPath } = await openBridge(directory, reasons.map((reason) => entry(reason, `uuid-${reason}`)))
    const appended = await bridge.poll()
    expect(appended).toBe(4)
    const rows = await continuationRows(ledgerPath)
    expect(rows).toHaveLength(4)
    for (const [index, reason] of reasons.entries()) {
      expect(rows[index]?.decision.action).toBe("ESCALATE")
      expect(rows[index]?.decision.confidence).toBeGreaterThanOrEqual(0.7)
      expect(rows[index]?.continuation['source']).toBe("continuation")
      expect(rows[index]?.continuation['reason']).toBe(reason)
      expect(rows[index]?.continuation['uuid']).toBe(`uuid-${reason}`)
      expect(rows[index]?.continuation['fingerprint']).toHaveLength(64)
    }
  })

  test("QA scenario 2: restart + re-emit dedupes; different uuid imports once; zero prompts", async () => {
    const directory = await mkdtemp(join(tmpdir(), "supervisor-bridge-")); paths.push(directory)
    const first = entry("resume_fallback", "u1")
    const { ledgerPath } = await openBridge(directory, [first])
    const bridge1 = new ContinuationBridge({
      statePath: join(directory, "journal-bridge.json"),
      read: async () => [first],
      append: async (type, payload) => { const ledger = await Ledger.open(ledgerPath); await ledger.append(type, payload) },
    })
    expect(await bridge1.poll()).toBe(1)

    // Restart: cursor points past the entry — re-read emits nothing.
    const bridge2 = new ContinuationBridge({
      statePath: join(directory, "journal-bridge.json"),
      read: async () => [],
      append: async (type, payload) => { const ledger = await Ledger.open(ledgerPath); await ledger.append(type, payload) },
    })
    expect(await bridge2.poll()).toBe(0)

    // Same alert re-emitted under a NEW journal cursor: fingerprint dedupe still holds.
    const reEmitted = mk("cursor-new", first.message)
    const bridge3 = new ContinuationBridge({
      statePath: join(directory, "journal-bridge.json"),
      read: async () => [reEmitted],
      append: async (type, payload) => { const ledger = await Ledger.open(ledgerPath); await ledger.append(type, payload) },
    })
    expect(await bridge3.poll()).toBe(0)

    // A different uuid is a new alert: exactly one new row.
    const bridge4 = new ContinuationBridge({
      statePath: join(directory, "journal-bridge.json"),
      read: async () => [entry("resume_fallback", "u2")],
      append: async (type, payload) => { const ledger = await Ledger.open(ledgerPath); await ledger.append(type, payload) },
    })
    expect(await bridge4.poll()).toBe(1)
    const rows = await continuationRows(ledgerPath)
    expect(rows).toHaveLength(2)
    expect(rows[1]?.continuation['uuid']).toBe("u2")
  })

  test("non-matching entries advance the cursor without importing", async () => {
    const directory = await mkdtemp(join(tmpdir(), "supervisor-bridge-")); paths.push(directory)
    const noise = mk("cursor-noise", "restart-continuation: some informational line without suffix")
    const { bridge, ledgerPath } = await openBridge(directory, [noise])
    expect(await bridge.poll()).toBe(0)
    expect(await continuationRows(ledgerPath)).toHaveLength(0)
  })
})
