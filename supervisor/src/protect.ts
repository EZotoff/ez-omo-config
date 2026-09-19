import { randomUUID } from "node:crypto"
import { mkdir, readFile, rename, writeFile } from "node:fs/promises"
import { dirname } from "node:path"
import type { ISO8601 } from "./types"

export const PROTECTION_SCHEMA_VERSION = 1

/**
 * Operator protection overlay (D295 feedback): "unless I interrupted the session
 * myself ... we can create a special command to close sessions like this to
 * protect them from auto-continuations by Supervisor". Protection is an
 * operator decision record — it never deletes or rewrites session history.
 */
export type ProtectionEntry = {
  readonly sessionID: string
  readonly reason?: string
  readonly since: ISO8601
}

export type ProtectionChange = {
  readonly at: ISO8601
  readonly action: "protect" | "unprotect"
  readonly sessionID: string
  readonly reason?: string
}

export type ProtectionFile = {
  readonly schemaVersion: number
  readonly protected: Readonly<Record<string, ProtectionEntry>>
  readonly history: readonly ProtectionChange[]
}

const emptyFile = (): ProtectionFile => ({ schemaVersion: PROTECTION_SCHEMA_VERSION, protected: {}, history: [] })

async function loadProtection(path: string): Promise<ProtectionFile> {
  try {
    const parsed = JSON.parse(await readFile(path, "utf8")) as ProtectionFile
    if (parsed.schemaVersion !== PROTECTION_SCHEMA_VERSION) throw new Error(`unsupported protection registry schema ${parsed.schemaVersion}`)
    return parsed
  } catch (error) {
    if (error instanceof Error && "code" in error && error.code === "ENOENT") return emptyFile()
    throw error
  }
}

/** Persisted registry of operator-protected sessions; atomic writes, append-only change history. */
export class ProtectionRegistry {
  private constructor(
    private readonly path: string,
    private file: ProtectionFile,
  ) {}

  static async open(path: string): Promise<ProtectionRegistry> {
    return new ProtectionRegistry(path, await loadProtection(path))
  }

  get entries(): readonly ProtectionEntry[] {
    return Object.values(this.file.protected)
  }

  get history(): readonly ProtectionChange[] {
    return this.file.history
  }

  isProtected(sessionID: string): boolean {
    return this.file.protected[sessionID] !== undefined
  }

  async protect(sessionID: string, options: { readonly reason?: string; readonly now?: ISO8601 } = {}): Promise<ProtectionEntry> {
    const existing = this.file.protected[sessionID]
    if (existing !== undefined) return existing
    const now = options.now ?? new Date().toISOString()
    const entry: ProtectionEntry = { sessionID, since: now, ...(options.reason === undefined ? {} : { reason: options.reason }) }
    this.file = {
      schemaVersion: PROTECTION_SCHEMA_VERSION,
      protected: { ...this.file.protected, [sessionID]: entry },
      history: [...this.file.history, { at: now, action: "protect", sessionID, ...(options.reason === undefined ? {} : { reason: options.reason }) }],
    }
    await this.persist()
    return entry
  }

  /** Returns false when the session was not protected (idempotent unprotect). */
  async unprotect(sessionID: string, now: ISO8601 = new Date().toISOString()): Promise<boolean> {
    if (this.file.protected[sessionID] === undefined) return false
    const nextProtected = { ...this.file.protected }
    delete nextProtected[sessionID]
    this.file = {
      schemaVersion: PROTECTION_SCHEMA_VERSION,
      protected: nextProtected,
      history: [...this.file.history, { at: now, action: "unprotect", sessionID }],
    }
    await this.persist()
    return true
  }

  private async persist(): Promise<void> {
    await mkdir(dirname(this.path), { recursive: true })
    const temporary = `${this.path}.tmp-${process.pid}-${randomUUID()}`
    await writeFile(temporary, JSON.stringify(this.file, null, 2), { mode: 0o600 })
    await rename(temporary, this.path)
  }
}
