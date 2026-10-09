import { afterEach, describe, expect, test } from "bun:test"
import { mkdtemp, rm } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { Ledger } from "../src/ledger"
import { ContinuationBridge, decodeJournalJson, parseContinuationAlert, type BridgeConfig, type JournalEntry } from "../src/journalbridge"

const paths: string[] = []
afterEach(async () => Promise.all(paths.splice(0).map((path) => rm(path, { recursive: true, force: true }))))

const mk = (cursor: string, message: string): JournalEntry => ({ cursor, message })

function entry(reason: string, uuid: string, unit = "opencode-interactive.service"): JournalEntry {
  return mk(`cursor-${reason}-${uuid}`, `restart-continuation: test alert unit=${unit} reason=${reason} rc=- uuid=${uuid} count=2 ts=1695000000`)
}

type BridgeOptions = {
  readonly config?: BridgeConfig
  readonly now?: () => number
}

function makeBridge(
  directory: string,
  ledgerPath: string,
  read: (afterCursor: string | undefined) => Promise<readonly JournalEntry[]>,
  options: BridgeOptions = {},
): ContinuationBridge {
  return new ContinuationBridge({
    statePath: join(directory, "journal-bridge.json"),
    read,
    append: async (type, payload) => {
      const ledger = await Ledger.open(ledgerPath)
      await ledger.append(type, payload)
    },
    ...(options.config !== undefined ? { config: options.config } : {}),
    ...(options.now !== undefined ? { now: options.now } : {}),
  })
}

async function openBridge(directory: string, entries: JournalEntry[], options: BridgeOptions = {}): Promise<{ bridge: ContinuationBridge; ledgerPath: string }> {
  const ledgerPath = join(directory, "ledger.jsonl")
  await Ledger.open(ledgerPath)
  const bridge = makeBridge(directory, ledgerPath, async (afterCursor) => {
    if (afterCursor === undefined) return entries
    const index = entries.findIndex((e) => e.cursor === afterCursor)
    return index === -1 ? [] : entries.slice(index + 1)
  }, options)
  return { bridge, ledgerPath }
}

type DecisionRow = { decision: { action: string; confidence: number; rationale: string }; continuation: Record<string, string> }

async function continuationRows(path: string): Promise<DecisionRow[]> {
  const ledger = await Ledger.open(path)
  return ledger.records
    .filter((record) => record.type === "TICK_DECIDED")
    .map((record) => record.payload as DecisionRow)
}

async function rawRows(path: string): Promise<Record<string, string>[]> {
  const ledger = await Ledger.open(path)
  return ledger.records
    .filter((record) => record.type === "CONTINUATION_ALERT")
    .map((record) => record.payload as Record<string, string>)
}

const config = (overrides: Partial<BridgeConfig> = {}): BridgeConfig => ({
  coalesceEnabled: true,
  coalesceWindowS: 900,
  maxEscalationsPerUnitPerWindow: 5,
  cooldownS: 3600,
  excludedUnits: [],
  ...overrides,
})

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
    const bridge1 = makeBridge(directory, ledgerPath, async () => [first])
    expect(await bridge1.poll()).toBe(1)

    // Restart: cursor points past the entry — re-read emits nothing.
    const bridge2 = makeBridge(directory, ledgerPath, async () => [])
    expect(await bridge2.poll()).toBe(0)

    // Same alert re-emitted under a NEW journal cursor: fingerprint dedupe still holds.
    const reEmitted = mk("cursor-new", first.message)
    const bridge3 = makeBridge(directory, ledgerPath, async () => [reEmitted])
    expect(await bridge3.poll()).toBe(0)

    // A different uuid is a new alert within the window: one digest escalation.
    const bridge4 = makeBridge(directory, ledgerPath, async () => [entry("resume_fallback", "u2")])
    expect(await bridge4.poll()).toBe(1)
    const rows = await continuationRows(ledgerPath)
    expect(rows).toHaveLength(2)
    expect(rows[1]?.continuation['uuid']).toBe("u2")
    expect(rows[1]?.continuation['digest']).toBe("true")
  })

  test("non-matching entries advance the cursor without importing", async () => {
    const directory = await mkdtemp(join(tmpdir(), "supervisor-bridge-")); paths.push(directory)
    const noise = mk("cursor-noise", "restart-continuation: some informational line without suffix")
    const { bridge, ledgerPath } = await openBridge(directory, [noise])
    expect(await bridge.poll()).toBe(0)
    expect(await continuationRows(ledgerPath)).toHaveLength(0)
    expect(await rawRows(ledgerPath)).toHaveLength(0)
  })

  test("burst replay: N same-key alerts in one pass → exactly 1 ESCALATE + N raw rows", async () => {
    const directory = await mkdtemp(join(tmpdir(), "supervisor-bridge-")); paths.push(directory)
    const entries = [entry("resume_fallback", "b1"), entry("resume_fallback", "b2"), entry("resume_fallback", "b3")]
    const { bridge, ledgerPath } = await openBridge(directory, entries)
    const appended = await bridge.poll()
    expect(appended).toBe(1)
    const rows = await continuationRows(ledgerPath)
    expect(rows).toHaveLength(1)
    expect(rows[0]?.decision.action).toBe("ESCALATE")
    expect(rows[0]?.continuation['events']).toBe("3")
    expect(rows[0]?.continuation['aggregate_count']).toBe("6")
    expect(rows[0]?.decision.rationale).toContain("uuid=b1")
    expect(rows[0]?.decision.rationale).toContain("ts=1695000000")
    const raw = await rawRows(ledgerPath)
    expect(raw).toHaveLength(3)
    expect(raw.map((row) => row['uuid']).sort()).toEqual(["b1", "b2", "b3"])
  })

  test("digest escalation: second same-key pass within window → 1 digest, no new primary", async () => {
    const directory = await mkdtemp(join(tmpdir(), "supervisor-bridge-")); paths.push(directory)
    const ledgerPath = join(directory, "ledger.jsonl")
    await Ledger.open(ledgerPath)
    let nowMs = 1_000_000_000_000
    const bridge1 = makeBridge(directory, ledgerPath, async () => [entry("resume_fallback", "d1")], { now: () => nowMs })
    expect(await bridge1.poll()).toBe(1)
    nowMs += 60_000 // 60s later — within the 900s window
    const bridge2 = makeBridge(directory, ledgerPath, async () => [entry("resume_fallback", "d2")], { now: () => nowMs })
    expect(await bridge2.poll()).toBe(1)
    const rows = await continuationRows(ledgerPath)
    expect(rows).toHaveLength(2)
    expect(rows[1]?.continuation['digest']).toBe("true")
    expect(rows[1]?.continuation['suppressed']).toBe("1")
    expect(rows[1]?.decision.rationale).toContain("1 repeat")
    expect(await rawRows(ledgerPath)).toHaveLength(2)
  })

  test("cooldown breaker: max escalations per unit then suppress (raw row preserved)", async () => {
    const directory = await mkdtemp(join(tmpdir(), "supervisor-bridge-")); paths.push(directory)
    const entries = [entry("preflight_failed", "c1"), entry("snapshot_failed", "c2"), entry("resume_fallback", "c3")]
    const { bridge, ledgerPath } = await openBridge(directory, entries, { config: config({ maxEscalationsPerUnitPerWindow: 2 }) })
    const appended = await bridge.poll()
    expect(appended).toBe(2)
    expect(await continuationRows(ledgerPath)).toHaveLength(2)
    expect(await rawRows(ledgerPath)).toHaveLength(3)
  })

  test("restart persistence: fresh bridge on same statePath, second same-key event within window → digest rolls", async () => {
    const directory = await mkdtemp(join(tmpdir(), "supervisor-bridge-")); paths.push(directory)
    const ledgerPath = join(directory, "ledger.jsonl")
    await Ledger.open(ledgerPath)
    let nowMs = 1_000_000_000_000
    const bridge1 = makeBridge(directory, ledgerPath, async () => [entry("resume_fallback", "p1")], { now: () => nowMs })
    expect(await bridge1.poll()).toBe(1)
    nowMs += 30_000
    const bridge2 = makeBridge(directory, ledgerPath, async () => [entry("resume_fallback", "p2")], { now: () => nowMs })
    expect(await bridge2.poll()).toBe(1)
    const rows = await continuationRows(ledgerPath)
    expect(rows).toHaveLength(2)
    expect(rows[1]?.continuation['digest']).toBe("true")
    expect(rows[1]?.continuation['uuid']).toBe("p2")
  })

  test("excluded_units: no escalation, raw row preserved", async () => {
    const directory = await mkdtemp(join(tmpdir(), "supervisor-bridge-")); paths.push(directory)
    const { bridge, ledgerPath } = await openBridge(directory, [entry("resume_fallback", "e1")], { config: config({ excludedUnits: ["opencode-interactive.service"] }) })
    expect(await bridge.poll()).toBe(0)
    expect(await continuationRows(ledgerPath)).toHaveLength(0)
    expect(await rawRows(ledgerPath)).toHaveLength(1)
  })

  test("coalesce_enabled=false: legacy one ESCALATE per alert", async () => {
    const directory = await mkdtemp(join(tmpdir(), "supervisor-bridge-")); paths.push(directory)
    const entries = [entry("resume_fallback", "x1"), entry("resume_fallback", "x2")]
    const { bridge, ledgerPath } = await openBridge(directory, entries, { config: config({ coalesceEnabled: false }) })
    expect(await bridge.poll()).toBe(2)
    expect(await continuationRows(ledgerPath)).toHaveLength(2)
    expect(await rawRows(ledgerPath)).toHaveLength(2)
  })
})
