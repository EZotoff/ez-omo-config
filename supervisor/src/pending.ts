import { randomUUID } from "node:crypto"
import { mkdir, open, readFile, rename } from "node:fs/promises"
import { dirname } from "node:path"
import { z } from "zod"
import { assertNever, type TargetRejectionReason } from "./types"

const recordSchema = z.object({
  root: z.string().min(1), sessionID: z.string().min(1),
  reason: z.enum(["missing-context", "origin-excluded"]),
  targetUserMessageID: z.string().min(1).optional(),
  createdAt: z.number().nonnegative(), attempts: z.number().int().nonnegative(),
  nextAttemptAt: z.number().nonnegative(),
  disposition: z.enum(["open", "resolved", "exhausted"]),
}).strict()
export type PendingAttention = z.infer<typeof recordSchema>
type Skip = { readonly root: string; readonly sessionID: string; readonly reason: TargetRejectionReason; readonly targetUserMessageID?: string }
type Key = { readonly root: string; readonly sessionID: string }
const keyOf = (input: Key): string => JSON.stringify([input.root, input.sessionID])

export function retryableTargetReason(reason: TargetRejectionReason): reason is PendingAttention["reason"] {
  switch (reason) {
    case "missing-context":
    case "origin-excluded": return true
    case "stale-target":
    case "aborted":
    case "protected": return false
    default: return assertNever(reason)
  }
}

export class PendingAttentionStore {
  private readonly entries = new Map<string, PendingAttention>()
  private writes: Promise<void> = Promise.resolve()
  private constructor(private readonly deps: {
    readonly path: string; readonly now: () => number
    readonly maxAttempts: number; readonly backoffS: readonly number[]
  }) {}

  static async open(deps: PendingAttentionStore["deps"]): Promise<PendingAttentionStore> {
    const store = new PendingAttentionStore(deps)
    try {
      const records = z.array(recordSchema).parse(JSON.parse(await readFile(deps.path, "utf8")))
      for (const record of records) store.entries.set(keyOf(record), record)
    } catch (error) {
      if (!(error instanceof Error && "code" in error && error.code === "ENOENT")) throw error
    }
    return store
  }

  get records(): readonly PendingAttention[] { return [...this.entries.values()] }
  due(): readonly PendingAttention[] {
    return this.records.filter((record) => record.disposition === "open" && record.nextAttemptAt <= this.deps.now())
  }

  private async save(): Promise<void> {
    const snapshot = JSON.stringify(this.records)
    const write = this.writes.then(async () => {
      await mkdir(dirname(this.deps.path), { recursive: true })
      const temporary = `${this.deps.path}.tmp-${process.pid}-${randomUUID()}`
      const handle = await open(temporary, "w", 0o600)
      try { await handle.writeFile(snapshot); await handle.sync() } finally { await handle.close() }
      await rename(temporary, this.deps.path)
    })
    this.writes = write.catch(() => undefined)
    await write
  }

  async record(input: Skip): Promise<PendingAttention | undefined> {
    if (!retryableTargetReason(input.reason)) { await this.resolve(input); return undefined }
    const key = keyOf(input)
    const previous = this.entries.get(key)
    if (previous !== undefined && previous.disposition !== "resolved") {
      const record = { ...previous, reason: input.reason, disposition: previous.attempts >= this.deps.maxAttempts ? "exhausted" as const : previous.disposition }
      this.entries.set(key, record)
      await this.save()
      return record
    }
    const firstDelay = this.deps.backoffS[0]
    if (firstDelay === undefined) throw new RangeError("pending attention requires a backoff")
    const record: PendingAttention = {
      ...input, reason: input.reason, createdAt: this.deps.now(), attempts: 0,
      nextAttemptAt: this.deps.now() + firstDelay * 1000, disposition: "open",
    }
    this.entries.set(key, record)
    await this.save()
    return record
  }

  async beginAttempt(input: Key): Promise<PendingAttention | undefined> {
    const key = keyOf(input)
    const previous = this.entries.get(key)
    if (previous === undefined || previous.disposition !== "open") return undefined
    if (previous.attempts >= this.deps.maxAttempts) {
      const exhausted = { ...previous, disposition: "exhausted" as const }
      this.entries.set(key, exhausted)
      await this.save()
      return exhausted
    }
    const attempts = previous.attempts + 1
    const delay = this.deps.backoffS[attempts] ?? this.deps.backoffS.at(-1)
    if (delay === undefined) throw new RangeError("pending attention requires a backoff")
    const record = { ...previous, attempts, nextAttemptAt: this.deps.now() + delay * 1000 }
    this.entries.set(key, record)
    await this.save()
    return record
  }

  async resolve(input: Key): Promise<void> {
    const key = keyOf(input)
    const previous = this.entries.get(key)
    if (previous === undefined || previous.disposition !== "open") return
    this.entries.set(key, { ...previous, disposition: "resolved" })
    await this.save()
  }
}
