// Reader-side contract obligations for operator-view.json (orca-transition plan
// Task 3; docs/portable-supervisor-contract.md "Reader obligations (c)"). This
// module is the portable READ side — the contract, not the publisher, is Orca's
// future API — so it deliberately has NO Supervisor-loop dependencies: only a
// type-only import from the publisher, an injectable fs adapter, and injectable
// wall/monotonic clocks. Everything here can be copied into Orca unchanged.
import { readFile } from "node:fs/promises"
import { z } from "zod"
import type { OperatorView, OperatorViewCard } from "./operator-view"

/** Contract: stale = producedAt older than 30 s at receipt. */
export const READ_STALE_AGE_MS = 30_000
/** Contract: producedAt more than 5 s in the future = future-skew freeze. */
export const READ_FUTURE_SKEW_MS = 5_000
/** Contract: a wall-clock jump beyond ±5 s must force a fresh read, never extend validity. */
export const READ_CLOCK_JUMP_MS = 5_000
/** Contract: poll at most every 5 s (freeze lands within 5 s after the 30 s budget expires). */
export const READ_MAX_POLL_MS = 5_000
/** Reader-side mirror of the publisher's MAX_CARDS bound (schema validation rejects larger sets). */
export const READER_MAX_CARDS = 20

const cardSchema = z
  .object({
    id: z.string().min(1),
    rootLabel: z.string(),
    sessionLabel: z.string(),
    reasonText: z.string(),
    premiseTexts: z.array(z.string()),
    ageSeconds: z.number().finite().nonnegative(),
    severity: z.enum(["A", "B", "C", "D"]),
    jumpAvailable: z.literal(true),
  })
  .strict()

const viewSchema = z
  .object({
    schemaVersion: z.literal(1),
    generation: z.number().int().positive(),
    lastSeq: z.number().int().nonnegative(),
    producedAt: z.string().refine((value) => !Number.isNaN(Date.parse(value))),
    cards: z.array(cardSchema).max(READER_MAX_CARDS),
  })
  .strict()

export type FreezeReason =
  | "read-error"
  | "invalid-schema"
  | "stale"
  | "future-skew"
  | "generation-regression"
  | "missing-updates"
  | "clock-jump"

export type ReadOutcome =
  | { readonly state: "live"; readonly view: OperatorView }
  | { readonly state: "frozen"; readonly reason: FreezeReason; readonly lastGood: OperatorView | undefined }

export type FsAdapter = { readonly readFile: (path: string) => Promise<string> }

const nodeFsAdapter: FsAdapter = { readFile: (path) => readFile(path, "utf8") }

/** Schema validation: parse + shape-check raw file bytes into an OperatorView, or undefined. */
export function parseOperatorView(raw: string): OperatorView | undefined {
  let parsed: unknown
  try {
    parsed = JSON.parse(raw)
  } catch {
    return undefined
  }
  const result = viewSchema.safeParse(parsed)
  if (!result.success) return undefined
  const cards: readonly OperatorViewCard[] = result.data.cards
  return {
    schemaVersion: 1,
    generation: result.data.generation,
    lastSeq: result.data.lastSeq,
    producedAt: result.data.producedAt,
    cards,
  }
}

export type OperatorViewReaderOptions = {
  readonly path: string
  readonly fs?: FsAdapter
  readonly wallMs?: () => number
  readonly monoMs?: () => number
}

/**
 * Single-image reader enforcing the contract's reader obligations: schema
 * validation, receipt-time staleness (30 s past / 5 s future), monotonic
 * (generation,lastSeq) tracking (older generation or a lastSeq gap/regression
 * freezes), and post-receipt freshness on a monotonic timer where a ±5 s
 * wall-clock jump refuses to extend validity.
 */
export class OperatorViewReader {
  private readonly path: string
  private readonly fs: FsAdapter
  private readonly wallMs: () => number
  private readonly monoMs: () => number
  private prev?: { readonly generation: number; readonly lastSeq: number }
  private lastGood: OperatorView | undefined
  private anchorWallMs = 0
  private anchorMonoMs = 0
  private anchored = false

  constructor(options: OperatorViewReaderOptions) {
    this.path = options.path
    this.fs = options.fs ?? nodeFsAdapter
    this.wallMs = options.wallMs ?? Date.now
    this.monoMs = options.monoMs ?? Date.now
  }

  private frozen(reason: FreezeReason): ReadOutcome {
    return { state: "frozen", reason, lastGood: this.lastGood }
  }

  /** Fresh read of the file image (reread on rename: every call goes to disk). */
  async read(): Promise<ReadOutcome> {
    let raw: string
    try {
      raw = await this.fs.readFile(this.path)
    } catch {
      return this.frozen("read-error")
    }
    const view = parseOperatorView(raw)
    if (view === undefined) return this.frozen("invalid-schema")
    const wall = this.wallMs()
    const producedMs = Date.parse(view.producedAt)
    if (wall - producedMs > READ_STALE_AGE_MS) return this.frozen("stale")
    if (producedMs - wall > READ_FUTURE_SKEW_MS) return this.frozen("future-skew")
    const prev = this.prev
    if (prev !== undefined) {
      if (view.generation < prev.generation) return this.frozen("generation-regression")
      // Lexicographic (generation,lastSeq) must never regress; within one
      // generation a changed lastSeq means updates were missed (gap/jump).
      if (view.lastSeq < prev.lastSeq) return this.frozen("missing-updates")
      if (view.generation === prev.generation && view.lastSeq !== prev.lastSeq) return this.frozen("missing-updates")
    }
    this.prev = { generation: view.generation, lastSeq: view.lastSeq }
    this.lastGood = view
    this.anchorWallMs = wall
    this.anchorMonoMs = this.monoMs()
    this.anchored = true
    return { state: "live", view }
  }

  /**
   * Post-receipt freshness recheck on a MONOTONIC timer: stale once 30 s of
   * monotonic time elapsed since receipt, and a wall clock that diverged from
   * the monotonic extrapolation by more than ±5 s (backward or forward) does
   * not extend validity — the caller must perform a fresh read().
   */
  validity(wallMs: number, monoMs: number): ReadOutcome {
    if (!this.anchored || this.lastGood === undefined) return this.frozen("read-error")
    if (monoMs - this.anchorMonoMs > READ_STALE_AGE_MS) return this.frozen("stale")
    const extrapolatedWall = this.anchorWallMs + (monoMs - this.anchorMonoMs)
    if (Math.abs(wallMs - extrapolatedWall) > READ_CLOCK_JUMP_MS) return this.frozen("clock-jump")
    return { state: "live", view: this.lastGood }
  }
}
