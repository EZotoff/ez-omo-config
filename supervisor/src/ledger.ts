import { createHash, randomUUID } from "node:crypto"
import { open, mkdir, readFile, rename, truncate } from "node:fs/promises"
import { dirname } from "node:path"
import { z } from "zod"
import { LEDGER_TYPES, type LedgerRecord, type LedgerRecordType } from "./types"

const recordSchema = z.object({
  seq: z.number().int().positive(), timestamp: z.string(), type: z.enum(LEDGER_TYPES), payload: z.unknown(),
  prevHash: z.string(), hash: z.string().length(64),
}).strict()

const digest = (record: Pick<LedgerRecord, "prevHash" | "seq" | "type" | "payload">): string =>
  createHash("sha256").update(JSON.stringify({
    prevHash: record.prevHash,
    seq: record.seq,
    type: record.type,
    payload: record.payload,
  })).digest("hex")

export class LedgerIntegrityError extends Error {
  readonly name = "LedgerIntegrityError"
  constructor(readonly seq: number, readonly reason: string) {
    super(`ledger integrity failure at sequence ${seq}: ${reason}`)
  }
}

async function atomicWrite(path: string, content: string): Promise<void> {
  await mkdir(dirname(path), { recursive: true })
  const temporary = `${path}.tmp-${process.pid}-${randomUUID()}`
  const handle = await open(temporary, "w", 0o600)
  try {
    await handle.writeFile(content)
    await handle.sync()
  } finally {
    await handle.close()
  }
  await rename(temporary, path)
}

export class Ledger {
  private constructor(readonly path: string, readonly records: readonly LedgerRecord[], readonly recoveredPartialTail: boolean) {}

  static async open(path: string): Promise<Ledger> {
    await mkdir(dirname(path), { recursive: true })
    let bytes: Uint8Array
    try {
      bytes = await readFile(path)
    } catch (error) {
      if (error instanceof Error && "code" in error && error.code === "ENOENT") return new Ledger(path, [], false)
      throw error
    }
    let recovered = false
    if (bytes.byteLength > 0 && bytes.at(-1) !== 10) {
      const boundary = bytes.lastIndexOf(10)
      await truncate(path, boundary + 1)
      bytes = bytes.slice(0, boundary + 1)
      recovered = true
    }
    const lines = new TextDecoder().decode(bytes).split("\n").filter((line) => line.length > 0)
    const records: LedgerRecord[] = []
    for (const line of lines) {
      const record = recordSchema.parse(JSON.parse(line))
      const expectedSeq = records.length + 1
      const expectedPrev = records.at(-1)?.hash ?? "GENESIS"
      if (record.seq !== expectedSeq) throw new LedgerIntegrityError(record.seq, "sequence mismatch")
      if (record.prevHash !== expectedPrev) throw new LedgerIntegrityError(record.seq, "previous hash mismatch")
      if (record.hash !== digest(record)) throw new LedgerIntegrityError(record.seq, "record hash mismatch")
      records.push(record)
    }
    const ledger = new Ledger(path, records, recovered)
    return recovered ? ledger.withRecord(await ledger.createRecord("ERROR", { reason: "partial ledger tail recovered" })) : ledger
  }

  private createRecord(type: LedgerRecordType, payload: unknown): LedgerRecord {
    const core = { prevHash: this.records.at(-1)?.hash ?? "GENESIS", seq: this.records.length + 1, type, payload }
    return { ...core, timestamp: new Date().toISOString(), hash: digest(core) }
  }

  private async withRecord(record: LedgerRecord): Promise<Ledger> {
    const records = [...this.records, record]
    await atomicWrite(this.path, `${records.map((entry) => JSON.stringify(entry)).join("\n")}\n`)
    return new Ledger(this.path, records, this.recoveredPartialTail)
  }

  async append(type: LedgerRecordType, payload: unknown): Promise<Ledger> {
    const previous = appendLocks.get(this.path) ?? Promise.resolve()
    const operation = previous.then(async () => {
      const current = await Ledger.open(this.path)
      return current.withRecord(current.createRecord(type, payload))
    })
    appendLocks.set(this.path, operation.then(() => undefined, () => undefined))
    return operation
  }
}

const appendLocks = new Map<string, Promise<void>>()
