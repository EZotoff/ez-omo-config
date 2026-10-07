// Error-storm auto-investigation (2026-10-05 operator request): when the
// supervisor's rolling 1-hour ERROR count crosses a configured threshold,
// create a dedicated opencode session containing the investigation question.
// Fires at most once per hour window; the slot is consumed even if the
// dispatch fails, so a broken endpoint can never loop session creation.
import { randomUUID } from "node:crypto"
import { mkdir, readFile, rename, writeFile } from "node:fs/promises"
import { dirname } from "node:path"
import type { ConsoleClient } from "./console"

export type InvestigationConfig = { readonly enabled: boolean; readonly threshold: number }
export type ErrorHourState = { windowStart: number; count: number; toasted: boolean; investigated: boolean }

/** Narrow structural view of the client (OpencodeClient satisfies it; tests stub it). */
export type InvestigationClient = Pick<ConsoleClient, "createSession" | "promptAsync">

/** Narrow ledger seam: the service wraps Ledger.append so the helper never
 *  depends on the hash-chain class. Payloads are telemetry records only. */
export type InvestigationLedgerAppend = (
  type: "INTERVENTION_SENT" | "ERROR" | "INVESTIGATION_DEDUPED",
  payload: Record<string, unknown>,
) => Promise<void>

export type InvestigationOutcome =
  | { readonly dispatched: false; readonly reason: "disabled" | "already-investigated" | "below-threshold" }
  | { readonly dispatched: true; readonly sessionID: string }
  | { readonly dispatched: false; readonly reason: "dispatch-failed"; readonly error: string }

/** Stable fingerprint of an error message: session IDs normalized away so the
 * same failure keeps one signature across retries. */
export function errorSignature(raw: string): string {
  return raw.replace(/ses_[A-Za-z0-9]+/g, "ses_*").slice(0, 120).trim()
}

/** Cross-hour investigation memory: fingerprints of dispatched signatures,
 * persisted so a restart (or a new hour window) does not re-investigate the
 * same recurring error within the dedup window. */
export class InvestigationMemory {
  private readonly fingerprints: Array<{ signature: string; dispatchedAtMs: number }> = []
  private statePath?: string

  constructor(private readonly windowH = 6) {}

  async load(path: string): Promise<void> {
    this.statePath = path
    try {
      const bytes = await readFile(path)
      const parsed = JSON.parse(new TextDecoder().decode(bytes)) as { fingerprints?: Array<{ signature?: unknown; dispatchedAtMs?: unknown }> }
      for (const entry of parsed.fingerprints ?? []) {
        if (typeof entry.signature === "string" && typeof entry.dispatchedAtMs === "number") {
          this.fingerprints.push({ signature: entry.signature, dispatchedAtMs: entry.dispatchedAtMs })
        }
      }
    } catch {
      // Missing or corrupt state starts empty; first record recreates the file.
    }
  }

  recentlyDispatched(signature: string, nowMs: number): boolean {
    const windowMs = this.windowH * 3_600_000
    return this.fingerprints.some((entry) => entry.signature === signature && nowMs - entry.dispatchedAtMs < windowMs)
  }

  async record(signature: string, nowMs: number): Promise<void> {
    const windowMs = this.windowH * 3_600_000
    const kept = this.fingerprints.filter((entry) => entry.signature !== signature && nowMs - entry.dispatchedAtMs < windowMs)
    kept.push({ signature, dispatchedAtMs: nowMs })
    this.fingerprints.length = 0
    this.fingerprints.push(...kept)
    if (this.statePath === undefined) return
    // Unique tmp name + rename: same atomic-persist pattern as ConsoleChannel.
    const temporary = `${this.statePath}.tmp-${process.pid}-${randomUUID()}`
    await mkdir(dirname(this.statePath), { recursive: true })
    await writeFile(temporary, JSON.stringify({ fingerprints: this.fingerprints }, null, 2))
    await rename(temporary, this.statePath)
  }
}

export function investigationPrompt(root: string, count: number, peak: number, threshold: number): string {
  return [
    `[Supervisor] Error investigation — ${root}`,
    "",
    `The supervisor logged ${count} errors in the current hour (hourly peak ${peak}, threshold ${threshold}). Investigate what is causing these errors:`,
    "",
    "1. Classify recent supervisor ERROR records:",
    `   jq -r 'select(.type=="ERROR") | [.timestamp, (.payload.root // ""), .payload.error // .payload.reason] | @tsv' ~/.local/state/opencode-supervisor/ledger.jsonl | tail -100`,
    "2. Check the supervisor service log:",
    "   journalctl --user -u opencode-supervisor.service --no-pager | tail -100",
    "",
    "Report: the dominant error signatures, the component producing them, the root cause, and the minimal fix. Read-only: do not modify supervisor state files.",
  ].join("\n")
}

export async function maybeDispatchErrorInvestigation(input: {
  readonly client: InvestigationClient
  readonly append: InvestigationLedgerAppend
  readonly config: InvestigationConfig
  readonly errorHour: ErrorHourState
  readonly root: string
  readonly count: number
  readonly peak: number
  readonly signature?: string | undefined
  readonly dedupWindowH?: number
  readonly memory?: InvestigationMemory
  readonly nowMs?: number
}): Promise<InvestigationOutcome> {
  if (!input.config.enabled) return { dispatched: false, reason: "disabled" }
  if (input.errorHour.investigated) return { dispatched: false, reason: "already-investigated" }
  if (input.count < input.config.threshold) return { dispatched: false, reason: "below-threshold" }
  const nowMs = input.nowMs ?? Date.now()
  // Cross-hour dedup (2026-10-07): the same error signature already
  // investigated within the window skips session creation. The dedup path
  // still consumes the once-per-hour slot so the invariant above holds.
  if (input.memory !== undefined && input.signature !== undefined && input.memory.recentlyDispatched(input.signature, nowMs)) {
    input.errorHour.investigated = true
    await input.append("INVESTIGATION_DEDUPED", { root: input.root, signature: input.signature, windowH: input.dedupWindowH ?? 6 })
    return { dispatched: false, reason: "already-investigated" }
  }
  // Consume the once-per-window slot BEFORE any await: a slow or hanging
  // dispatch must never let the next error record double-fire a session.
  input.errorHour.investigated = true
  const title = `[Supervisor] error investigation (${input.root.split("/").at(-1) ?? input.root})`
  try {
    const session = await input.client.createSession(input.root, title)
    if (input.memory !== undefined && input.signature !== undefined) await input.memory.record(input.signature, nowMs)
    await input.append("INTERVENTION_SENT", {
      mode: "investigation",
      root: input.root,
      sessionID: session.id,
      count: input.count,
      peak: input.peak,
      threshold: input.config.threshold,
    })
    await input.client.promptAsync(session.id, input.root, investigationPrompt(input.root, input.count, input.peak, input.config.threshold))
    return { dispatched: true, sessionID: session.id }
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error)
    // ERROR record here is deliberately NOT fed back through
    // recordErrorTelemetry — no telemetry feedback loop.
    await input.append("ERROR", { root: input.root, reason: `error investigation dispatch failed: ${message}` })
    return { dispatched: false, reason: "dispatch-failed", error: message }
  }
}
