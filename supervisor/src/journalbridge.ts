import { createHash } from "node:crypto"
import { mkdir, open, readFile, rename } from "node:fs/promises"
import { dirname } from "node:path"
import { randomUUID } from "node:crypto"
import type { LedgerAppend } from "./queue"

/**
 * Journal→ledger continuation bridge (crashsafe plan, task 10).
 *
 * Imports `restart-continuation`-tagged journal alerts (machine-readable
 * key=value suffix contract emitted by scripts/restart-with-continuation.sh
 * journal_alert()) into the supervisor ledger as TICK_DECIDED escalations —
 * the shape Vox/Beacon already consume.
 *
 * HARD BOUNDARY: escalate-only. This module never touches OpencodeClient /
 * promptAsync / any session-writing API — single-writer rule (only
 * hook-resume injects prompts).
 */

export const CONTINUATION_REASONS = ["preflight_failed", "snapshot_failed", "resume_fallback", "db_fallback"] as const
export type ContinuationReason = (typeof CONTINUATION_REASONS)[number]

export type ContinuationAlert = {
  readonly unit: string
  readonly reason: ContinuationReason
  readonly rc: string
  readonly uuid: string
  readonly count: string
  readonly ts: string
  readonly fingerprint: string
}

export type JournalEntry = {
  readonly cursor: string
  readonly message: string
}

// Suffix contract: human text first, then "unit=<u> reason=<r> rc=<n|-> uuid=<u|-> count=<n|-> ts=<epoch>" at end.
const SUFFIX = / unit=(\S+) reason=(\S+) rc=(\S+) uuid=(\S+) count=(\S+) ts=(\S+)$/

export function fingerprintOf(unit: string, reason: string, uuid: string, ts: string): string {
  return createHash("sha256").update(`${unit}|${reason}|${uuid}|${ts}`).digest("hex")
}

export function parseContinuationAlert(message: string): ContinuationAlert | undefined {
  const match = SUFFIX.exec(message)
  if (match === null) return undefined
  const [, unit, reason, rc, uuid, count, ts] = match
  if ((CONTINUATION_REASONS as readonly string[]).every((candidate) => candidate !== reason)) return undefined
  if (unit === undefined || rc === undefined || uuid === undefined || count === undefined || ts === undefined) return undefined
  return { unit, reason: reason as ContinuationReason, rc, uuid, count, ts, fingerprint: fingerprintOf(unit, reason as ContinuationReason, uuid, ts) }
}

/**
 * journalctl -o json can emit concatenated JSON objects on one line when
 * entries are batched; decode tolerantly instead of assuming one-per-line.
 */
export function decodeJournalJson(output: string): JournalEntry[] {
  const entries: JournalEntry[] = []
  let index = 0
  const text = output.trim()
  while (index < text.length) {
    while (index < text.length && (text[index] === "\n" || text[index] === " ")) index += 1
    const start = text.indexOf("{", index)
    if (start === -1) break
    let depth = 0
    let inString = false
    let escaped = false
    let end = -1
    for (let position = start; position < text.length; position += 1) {
      const character = text[position]
      if (inString) {
        if (escaped) escaped = false
        else if (character === "\\") escaped = true
        else if (character === '"') inString = false
        continue
      }
      if (character === '"') inString = true
      else if (character === "{") depth += 1
      else if (character === "}") {
        depth -= 1
        if (depth === 0) {
          end = position
          break
        }
      }
    }
    if (end === -1) break
    let parsed: unknown
    try {
      parsed = JSON.parse(text.slice(start, end + 1))
    } catch {
      index = end + 1
      continue
    }
    const cursor = (parsed as { __CURSOR?: unknown }).__CURSOR
    const message = (parsed as { MESSAGE?: unknown }).MESSAGE
    if (typeof cursor === "string" && typeof message === "string") entries.push({ cursor, message })
    index = end + 1
  }
  return entries
}

export type JournalReader = (afterCursor: string | undefined) => Promise<readonly JournalEntry[]>

/** Production reader: bounded backlog on first run, cursor batches afterwards. */
export const readJournalEntries: JournalReader = async (afterCursor) => {
  const args = ["--user", "-t", "restart-continuation", "-o", "json", "--no-pager", "-n", "500"]
  if (afterCursor !== undefined) args.push("--after-cursor", afterCursor)
  const process_ = Bun.spawn(["journalctl", ...args], { stdout: "pipe", stderr: "ignore" })
  const output = await new Response(process_.stdout).text()
  await process_.exited
  return decodeJournalJson(output)
}

type BridgeState = {
  readonly schemaVersion: 1
  cursor: string | undefined
  fingerprints: string[]
}

const FINGERPRINT_CAP = 1000

async function loadState(path: string): Promise<BridgeState> {
  try {
    const raw = JSON.parse(await readFile(path, "utf8")) as { schemaVersion?: unknown; cursor?: unknown; fingerprints?: unknown }
    if (raw.schemaVersion === 1 && (raw.cursor === undefined || typeof raw.cursor === "string") && Array.isArray(raw.fingerprints)) {
      return { schemaVersion: 1, cursor: typeof raw.cursor === "string" ? raw.cursor : undefined, fingerprints: raw.fingerprints.filter((entry): entry is string => typeof entry === "string") }
    }
  } catch {
    // missing or unreadable state — start fresh (cursor undefined, no imports)
  }
  return { schemaVersion: 1, cursor: undefined, fingerprints: [] }
}

async function saveState(path: string, state: BridgeState): Promise<void> {
  await mkdir(dirname(path), { recursive: true })
  const temporary = `${path}.tmp-${process.pid}-${randomUUID()}`
  const handle = await open(temporary, "w", 0o600)
  try {
    await handle.writeFile(JSON.stringify(state))
    await handle.sync()
  } finally {
    await handle.close()
  }
  await rename(temporary, path)
}

export type BridgeDeps = {
  readonly statePath: string
  readonly read: JournalReader
  readonly append: LedgerAppend
}

export class ContinuationBridge {
  private state: BridgeState | undefined

  constructor(private readonly deps: BridgeDeps) {}

  private async currentState(): Promise<BridgeState> {
    this.state ??= await loadState(this.deps.statePath)
    return this.state
  }

  /**
   * One import pass: journal entries after the persisted cursor → at most one
   * TICK_DECIDED escalation per new alert fingerprint. Idempotent across
   * bridge/service restarts (persisted cursor + fingerprints).
   * Returns the number of escalations appended.
   */
  async poll(): Promise<number> {
    const state = await this.currentState()
    const entries = await this.deps.read(state.cursor)
    if (entries.length === 0) return 0
    const seen = new Set(state.fingerprints)
    let appended = 0
    for (const entry of entries) {
      const alert = parseContinuationAlert(entry.message)
      if (alert === undefined || seen.has(alert.fingerprint)) continue
      seen.add(alert.fingerprint)
      state.fingerprints.push(alert.fingerprint)
      await this.deps.append("TICK_DECIDED", {
        decision: {
          action: "ESCALATE",
          confidence: 0.9,
          rationale: `continuation alert: ${alert.reason} on ${alert.unit} (rc=${alert.rc}, count=${alert.count})`,
          citations: [],
        },
        continuation: {
          source: "continuation",
          unit: alert.unit,
          reason: alert.reason,
          rc: alert.rc,
          uuid: alert.uuid,
          count: alert.count,
          ts: alert.ts,
          fingerprint: alert.fingerprint,
        },
      })
      appended += 1
    }
    state.cursor = entries.at(-1)?.cursor ?? state.cursor
    if (state.fingerprints.length > FINGERPRINT_CAP) state.fingerprints = state.fingerprints.slice(-FINGERPRINT_CAP)
    await saveState(this.deps.statePath, state)
    return appended
  }
}
