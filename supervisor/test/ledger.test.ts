import { afterEach, describe, expect, test } from "bun:test"
import { mkdtemp, readFile, rm, truncate, writeFile } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { Ledger, LedgerIntegrityError } from "../src/ledger"

const paths: string[] = []
afterEach(async () => Promise.all(paths.splice(0).map((path) => rm(path, { recursive: true, force: true }))))

describe("Ledger", () => {
  test("appends and reloads a valid hash chain", async () => {
    const directory = await mkdtemp(join(tmpdir(), "supervisor-ledger-")); paths.push(directory)
    const path = join(directory, "ledger.jsonl")
    const ledger = await Ledger.open(path)
    await ledger.append("WORKER_TURN_COMPLETED", { sessionID: "ses-a" })
    expect((await Ledger.open(path)).records).toHaveLength(1)
  })

  test("truncates a corrupt partial tail and appends a recovery flag", async () => {
    const directory = await mkdtemp(join(tmpdir(), "supervisor-tail-")); paths.push(directory)
    const path = join(directory, "ledger.jsonl")
    const ledger = await Ledger.open(path)
    await ledger.append("WORKER_TURN_COMPLETED", { sessionID: "ses-a" })
    await ledger.append("TICK_DECIDED", { action: "ACCEPT" })
    const size = (await readFile(path)).byteLength
    await truncate(path, size - 10)
    const recovered = await Ledger.open(path)
    expect(recovered.recoveredPartialTail).toBe(true)
    expect(recovered.records.at(-1)?.type).toBe("ERROR")
  })

  test("detects hash-chain tampering", async () => {
    const directory = await mkdtemp(join(tmpdir(), "supervisor-tamper-")); paths.push(directory)
    const path = join(directory, "ledger.jsonl")
    const ledger = await Ledger.open(path)
    await ledger.append("WORKER_TURN_COMPLETED", { sessionID: "ses-a" })
    const text = await readFile(path, "utf8")
    await writeFile(path, text.replace("ses-a", "ses-b"))
    expect(Ledger.open(path)).rejects.toBeInstanceOf(LedgerIntegrityError)
  })

  test("serializes concurrent appends without losing records", async () => {
    const directory = await mkdtemp(join(tmpdir(), "supervisor-concurrent-")); paths.push(directory)
    const path = join(directory, "ledger.jsonl")
    const ledger = await Ledger.open(path)
    await Promise.all(Array.from({ length: 20 }, (_value, index) => ledger.append("METRICS_SNAPSHOT", { index })))
    const loaded = await Ledger.open(path)
    expect(loaded.records.map((record) => record.seq)).toEqual(Array.from({ length: 20 }, (_value, index) => index + 1))
  })
})
