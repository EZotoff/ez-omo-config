import { createHash } from "node:crypto"
import { mkdir, open, readFile, rename } from "node:fs/promises"
import { dirname } from "node:path"
import { randomUUID } from "node:crypto"
import type { LedgerAppend } from "./queue"
import { assertNever } from "./types"

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

/** Coalescing/exclusion policy for the bridge (design 2, M4). */
export type BridgeConfig = {
  readonly coalesceEnabled: boolean
  readonly coalesceWindowS: number
  readonly maxEscalationsPerUnitPerWindow: number
  readonly cooldownS: number
  readonly excludedUnits: readonly string[]
}

export const DEFAULT_BRIDGE_CONFIG: BridgeConfig = {
  coalesceEnabled: true,
  coalesceWindowS: 900,
  maxEscalationsPerUnitPerWindow: 5,
  cooldownS: 3600,
  excludedUnits: [],
}

type CoalesceDecision =
  | { readonly kind: "excluded" }
  | { readonly kind: "cooling" }
  | { readonly kind: "coalesced" }
  | { readonly kind: "escalate" }

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

type CoalesceEntry = {
  windowStart: number
  escalations: number
  suppressed: number
  digestEmitted: boolean
}

type UnitBreaker = {
  windowStart: number
  escalations: number
  cooldownUntil: number
}

type BridgeState = {
  readonly schemaVersion: 1
  cursor: string | undefined
  fingerprints: string[]
  // Additive under schemaVersion 1: old code ignores these fields; new code
  // defaults them to {} when absent (safe rollback, no cursor reset).
  coalesce: Record<string, CoalesceEntry>
  breakers: Record<string, UnitBreaker>
}

const FINGERPRINT_CAP = 1000

function parseCoalesce(raw: unknown): Record<string, CoalesceEntry> {
  if (typeof raw !== "object" || raw === null || Array.isArray(raw)) return {}
  const out: Record<string, CoalesceEntry> = {}
  for (const [key, value] of Object.entries(raw as Record<string, unknown>)) {
    if (typeof value !== "object" || value === null) continue
    const entry = value as Record<string, unknown>
    if (typeof entry["windowStart"] !== "number" || typeof entry["escalations"] !== "number" || typeof entry["suppressed"] !== "number" || typeof entry["digestEmitted"] !== "boolean") continue
    out[key] = { windowStart: entry["windowStart"], escalations: entry["escalations"], suppressed: entry["suppressed"], digestEmitted: entry["digestEmitted"] }
  }
  return out
}

function parseBreakers(raw: unknown): Record<string, UnitBreaker> {
  if (typeof raw !== "object" || raw === null || Array.isArray(raw)) return {}
  const out: Record<string, UnitBreaker> = {}
  for (const [key, value] of Object.entries(raw as Record<string, unknown>)) {
    if (typeof value !== "object" || value === null) continue
    const entry = value as Record<string, unknown>
    if (typeof entry["windowStart"] !== "number" || typeof entry["escalations"] !== "number" || typeof entry["cooldownUntil"] !== "number") continue
    out[key] = { windowStart: entry["windowStart"], escalations: entry["escalations"], cooldownUntil: entry["cooldownUntil"] }
  }
  return out
}

async function loadState(path: string): Promise<BridgeState> {
  try {
    const raw = JSON.parse(await readFile(path, "utf8")) as { schemaVersion?: unknown; cursor?: unknown; fingerprints?: unknown; coalesce?: unknown; breakers?: unknown }
    if (raw.schemaVersion === 1 && (raw.cursor === undefined || typeof raw.cursor === "string") && Array.isArray(raw.fingerprints)) {
      return {
        schemaVersion: 1,
        cursor: typeof raw.cursor === "string" ? raw.cursor : undefined,
        fingerprints: raw.fingerprints.filter((entry): entry is string => typeof entry === "string"),
        coalesce: parseCoalesce(raw.coalesce),
        breakers: parseBreakers(raw.breakers),
      }
    }
  } catch {
    // missing or unreadable state — start fresh (cursor undefined, no imports)
  }
  return { schemaVersion: 1, cursor: undefined, fingerprints: [], coalesce: {}, breakers: {} }
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
  readonly config?: BridgeConfig
  readonly now?: () => number
}

export class ContinuationBridge {
  private state: BridgeState | undefined
  private readonly written = new Set<string>()

  constructor(private readonly deps: BridgeDeps) {}

  private async currentState(): Promise<BridgeState> {
    this.state ??= await loadState(this.deps.statePath)
    return this.state
  }

  /**
   * One import pass. Every new alert fingerprint is recorded as a raw
   * CONTINUATION_ALERT row; escalations are coalesced by unit|reason within a
   * window (first pass → one ESCALATE; later passes → one updated digest
   * escalation naming the suppressed count), with a per-unit cooldown breaker
   * and an excluded_units list. Idempotent across restarts (persisted cursor +
   * fingerprints + coalesce/breaker state). Returns the number of TICK_DECIDED
   * escalations appended (primary + digest).
   */
  async poll(): Promise<number> {
    const state = structuredClone(await this.currentState())
    const entries = await this.deps.read(state.cursor)
    if (entries.length === 0) return 0
    const config = this.deps.config ?? DEFAULT_BRIDGE_CONFIG
    const now = Math.floor((this.deps.now ?? Date.now)() / 1000)
    const seen = new Set(state.fingerprints)
    const fresh: ContinuationAlert[] = []
    for (const entry of entries) {
      const alert = parseContinuationAlert(entry.message)
      if (alert === undefined || seen.has(alert.fingerprint)) continue
      seen.add(alert.fingerprint)
      state.fingerprints.push(alert.fingerprint)
      fresh.push(alert)
    }
    // Raw rows: one CONTINUATION_ALERT per distinct new fingerprint, always.
    for (const alert of fresh) {
      await this.appendOnce("CONTINUATION_ALERT", {
        source: "continuation",
        unit: alert.unit,
        reason: alert.reason,
        rc: alert.rc,
        uuid: alert.uuid,
        count: alert.count,
        ts: alert.ts,
        fingerprint: alert.fingerprint,
      })
    }
    const excluded = new Set(config.excludedUnits)
    let escalations = 0
    if (!config.coalesceEnabled) {
      // Off-switch: legacy one-ESCALATE-per-alert behavior (exclusions still honored).
      for (const alert of fresh) {
        if (excluded.has(alert.unit)) continue
        await this.appendEscalate([alert])
        escalations += 1
      }
    } else {
      const groups = new Map<string, ContinuationAlert[]>()
      for (const alert of fresh) {
        const key = `${alert.unit}|${alert.reason}`
        const list = groups.get(key)
        if (list === undefined) groups.set(key, [alert])
        else list.push(alert)
      }
      for (const [key, alerts] of groups) {
        const head = alerts[0]
        if (head === undefined) continue
        const decision = this.decide(state, config, key, head.unit, now)
        switch (decision.kind) {
          case "excluded":
          case "cooling":
            break
          case "coalesced": {
            const entry = state.coalesce[key]
            if (entry === undefined) break
            entry.suppressed += alerts.length
            entry.digestEmitted = true
            await this.appendDigest(head, entry)
            escalations += 1
            break
          }
          case "escalate":
            await this.appendEscalate(alerts)
            escalations += 1
            break
          default:
            assertNever(decision)
        }
      }
    }
    state.cursor = entries.at(-1)?.cursor ?? state.cursor
    if (state.fingerprints.length > FINGERPRINT_CAP) state.fingerprints = state.fingerprints.slice(-FINGERPRINT_CAP)
    await saveState(this.deps.statePath, state)
    this.state = state
    this.written.clear()
    return escalations
  }

  private async appendOnce(...args: Parameters<LedgerAppend>): Promise<void> {
    const key = JSON.stringify(args)
    if (this.written.has(key)) return
    await this.deps.append(...args)
    this.written.add(key)
  }

  /** Exhaustive coalescing decision for one unit|reason group. Mutates state. */
  private decide(state: BridgeState, config: BridgeConfig, key: string, unit: string, now: number): CoalesceDecision {
    if (config.excludedUnits.includes(unit)) return { kind: "excluded" }
    const breaker = state.breakers[unit] ?? { windowStart: now, escalations: 0, cooldownUntil: 0 }
    if (now < breaker.cooldownUntil) {
      state.breakers[unit] = breaker
      return { kind: "cooling" }
    }
    if (now - breaker.windowStart >= config.coalesceWindowS) {
      breaker.windowStart = now
      breaker.escalations = 0
    }
    const entry = state.coalesce[key]
    if (entry !== undefined && now - entry.windowStart < config.coalesceWindowS) {
      state.breakers[unit] = breaker
      return { kind: "coalesced" }
    }
    if (breaker.escalations >= config.maxEscalationsPerUnitPerWindow) {
      breaker.cooldownUntil = now + config.cooldownS
      state.breakers[unit] = breaker
      return { kind: "cooling" }
    }
    breaker.escalations += 1
    state.breakers[unit] = breaker
    state.coalesce[key] = { windowStart: now, escalations: 1, suppressed: 0, digestEmitted: false }
    return { kind: "escalate" }
  }

  private async appendEscalate(alerts: readonly ContinuationAlert[]): Promise<void> {
    const head = alerts[0]
    if (head === undefined) return
    const aggregateCount = alerts.reduce((sum, alert) => sum + (Number.parseInt(alert.count, 10) || 0), 0)
    await this.appendOnce("TICK_DECIDED", {
      decision: {
        action: "ESCALATE",
        confidence: 0.9,
        rationale: `continuation alert: ${head.reason} on ${head.unit} (rc=${head.rc}, count=${head.count}, uuid=${head.uuid}, ts=${head.ts}, events=${alerts.length}, aggregate_count=${aggregateCount})`,
        citations: [],
      },
      continuation: {
        source: "continuation",
        unit: head.unit,
        reason: head.reason,
        rc: head.rc,
        uuid: head.uuid,
        count: head.count,
        ts: head.ts,
        fingerprint: head.fingerprint,
        events: String(alerts.length),
        aggregate_count: String(aggregateCount),
      },
    })
  }

  private async appendDigest(head: ContinuationAlert, entry: CoalesceEntry): Promise<void> {
    await this.appendOnce("TICK_DECIDED", {
      decision: {
        action: "ESCALATE",
        confidence: 0.9,
        rationale: `continuation alert digest: ${head.reason} on ${head.unit} — ${entry.suppressed} repeat(s) suppressed within the coalescing window (uuid=${head.uuid}, ts=${head.ts})`,
        citations: [],
      },
      continuation: {
        source: "continuation",
        unit: head.unit,
        reason: head.reason,
        rc: head.rc,
        uuid: head.uuid,
        count: head.count,
        ts: head.ts,
        fingerprint: head.fingerprint,
        digest: "true",
        suppressed: String(entry.suppressed),
      },
    })
  }
}
