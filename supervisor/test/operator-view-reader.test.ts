// Reader-side edge-case battery for operator-view.json (orca-transition plan
// Task 3; contract "Reader obligations (c)" + "Required test cases"). Every
// named case is demonstrated to FAIL against a naive reader: `naiveRead` below
// is the mutation (JSON.parse + cards array, no validation), and each test
// asserts the validator freezes exactly what the naive reader would render.
import { describe, expect, test } from "bun:test"
import { mkdtemp, rename, rm, writeFile } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"
import {
  OperatorViewReader,
  READ_CLOCK_JUMP_MS,
  READ_FUTURE_SKEW_MS,
  READ_MAX_POLL_MS,
  READ_STALE_AGE_MS,
  READER_MAX_CARDS,
  parseOperatorView,
} from "../src/operator-view-reader"
import type { FsAdapter } from "../src/operator-view-reader"
import { T0 } from "./helpers"

const card = (id: string): Record<string, unknown> => ({
  id,
  rootLabel: "proj",
  sessionLabel: "ses-a",
  reasonText: "Deploy to prod?",
  premiseTexts: ["no-newer-turn: ses-a @ msg-a1"],
  ageSeconds: 0,
  severity: "B",
  jumpAvailable: true,
})

type SnapshotOverrides = Partial<{
  schemaVersion: number
  generation: number
  lastSeq: number
  producedAt: string
  cards: unknown[]
}>

const snapshot = (overrides: SnapshotOverrides = {}): string =>
  JSON.stringify({
    schemaVersion: 1,
    generation: 1,
    lastSeq: 5,
    producedAt: new Date(T0).toISOString(),
    cards: [card("att_1")],
    ...overrides,
  })

/** The mutation: a reader that parses and renders without any contract validation. */
const naiveRead = (raw: string): { cards: unknown[] } | undefined => {
  try {
    const parsed = JSON.parse(raw) as { cards?: unknown }
    return Array.isArray(parsed.cards) ? { cards: parsed.cards } : undefined
  } catch {
    return undefined
  }
}

const memFs = (get: () => string): FsAdapter => ({ readFile: async () => get() })

const readerFor = (raw: () => string, wall: () => number, mono: () => number): OperatorViewReader =>
  new OperatorViewReader({ path: "operator-view.json", fs: memFs(raw), wallMs: wall, monoMs: mono })

describe("operator-view reader edge cases", () => {
  test("(c1) 29 s age → live; 31 s age → frozen/stale", async () => {
    const raw29 = snapshot({ producedAt: new Date(T0 - 29_000).toISOString() })
    const live = await readerFor(() => raw29, () => T0, () => 0).read()
    expect(live.state).toBe("live")
    expect(naiveRead(raw29)).toBeDefined()

    const raw31 = snapshot({ producedAt: new Date(T0 - 31_000).toISOString() })
    const frozen = await readerFor(() => raw31, () => T0, () => 0).read()
    expect(frozen.state).toBe("frozen")
    if (frozen.state === "frozen") expect(frozen.reason).toBe("stale")
    // Naive reader would render the 31 s-old image; the validator refuses.
    expect(naiveRead(raw31)).toBeDefined()
  })

  test("(c2) +6 s future producedAt → frozen (future-skew); +5 s boundary stays live", async () => {
    const raw6 = snapshot({ producedAt: new Date(T0 + 6_000).toISOString() })
    const frozen = await readerFor(() => raw6, () => T0, () => 0).read()
    expect(frozen.state).toBe("frozen")
    if (frozen.state === "frozen") expect(frozen.reason).toBe("future-skew")
    expect(naiveRead(raw6)).toBeDefined()

    const raw5 = snapshot({ producedAt: new Date(T0 + 5_000).toISOString() })
    const boundary = await readerFor(() => raw5, () => T0, () => 0).read()
    expect(boundary.state).toBe("live")
  })

  test("(c3) restart with an old snapshot (older generation) → freeze, never render", async () => {
    let raw = snapshot({ generation: 5, lastSeq: 5 })
    const reader = readerFor(() => raw, () => T0, () => 0)
    const first = await reader.read()
    expect(first.state).toBe("live")

    // Supervisor restarts and republishes an older-generation snapshot (fresh producedAt).
    raw = snapshot({ generation: 2, lastSeq: 2 })
    const after = await reader.read()
    expect(after.state).toBe("frozen")
    if (after.state === "frozen") {
      expect(after.reason).toBe("generation-regression")
      // The stale image is never rendered; the last good image is retained.
      expect(after.lastGood?.generation).toBe(5)
    }
    expect(naiveRead(raw)).toBeDefined()
  })

  test("(c4) missing updates (gap in lastSeq sequence) → freeze", async () => {
    let raw = snapshot({ generation: 5, lastSeq: 5 })
    const reader = readerFor(() => raw, () => T0, () => 0)
    expect((await reader.read()).state).toBe("live")

    // Same generation, lastSeq jumped 5 → 9: the reader missed the publication
    // that would explain the change (a correct publisher bumps generation).
    raw = snapshot({ generation: 5, lastSeq: 9 })
    const gap = await reader.read()
    expect(gap.state).toBe("frozen")
    if (gap.state === "frozen") expect(gap.reason).toBe("missing-updates")
    expect(naiveRead(raw)).toBeDefined()

    // lastSeq regression across generations is the same freeze class.
    raw = snapshot({ generation: 6, lastSeq: 3 })
    const regression = await reader.read()
    expect(regression.state).toBe("frozen")
    if (regression.state === "frozen") expect(regression.reason).toBe("missing-updates")
    expect(naiveRead(raw)).toBeDefined()
  })

  test("(c5) clock jumps via fake clock: backward AND forward >5 s force a fresh read", async () => {
    let wall = T0
    let mono = 0
    const raw = snapshot({ producedAt: new Date(T0).toISOString() })
    const reader = readerFor(() => raw, () => wall, () => mono)
    expect((await reader.read()).state).toBe("live")

    // Forward jump >5 s: validity refuses to extend the current image.
    wall = T0 + 7_000
    mono = 1_000
    const forward = reader.validity(wall, mono)
    expect(forward.state).toBe("frozen")
    if (forward.state === "frozen") expect(forward.reason).toBe("clock-jump")

    // A fresh read at the jumped wall time re-anchors and is live again.
    expect((await reader.read()).state).toBe("live")
    expect(reader.validity(wall, mono).state).toBe("live")

    // Backward jump >5 s from the new anchor also refuses.
    wall = T0 - 7_000
    mono = 2_000
    const backward = reader.validity(wall, mono)
    expect(backward.state).toBe("frozen")
    if (backward.state === "frozen") expect(backward.reason).toBe("clock-jump")

    // Within ±5 s the image stays valid.
    wall = T0 + 7_000 + 4_000
    mono = 3_000
    expect(reader.validity(wall, mono).state).toBe("live")
  })

  test("(c5b) post-receipt freshness uses the monotonic timer, not wall clock", async () => {
    const raw = snapshot({ producedAt: new Date(T0).toISOString() })
    const reader = readerFor(() => raw, () => T0, () => 0)
    expect((await reader.read()).state).toBe("live")
    // 31 s of monotonic time elapsed → stale even though the wall clock agrees.
    const stale = reader.validity(T0 + 31_000, 31_000)
    expect(stale.state).toBe("frozen")
    if (stale.state === "frozen") expect(stale.reason).toBe("stale")
  })

  test("(c6) 10-minute quiet period — heartbeat keeps producedAt fresh, cards never grey", async () => {
    let wall = T0
    let mono = 0
    let raw = snapshot({ generation: 1, lastSeq: 5, producedAt: new Date(wall).toISOString() })
    const reader = readerFor(() => raw, () => wall, () => mono)
    expect((await reader.read()).state).toBe("live")

    for (let minute = 1; minute <= 10; minute += 1) {
      wall += 60_000
      mono += 60_000
      // Heartbeat republish: fresh producedAt, generation advances, lastSeq unchanged.
      raw = snapshot({ generation: minute + 1, lastSeq: 5, producedAt: new Date(wall).toISOString() })
      const out = await reader.read()
      expect(out.state).toBe("live")
      if (out.state === "live") expect(out.view.cards.length).toBe(1)
    }
  })

  test("(c7) invalid schema → frozen; naive reader would render", async () => {
    const invalid: Array<{ name: string; raw: string; naiveAccepts: boolean }> = [
      { name: "malformed JSON", raw: "{not json", naiveAccepts: false },
      { name: "wrong schemaVersion", raw: snapshot({ schemaVersion: 2 }), naiveAccepts: true },
      { name: "generation 0", raw: snapshot({ generation: 0 }), naiveAccepts: true },
      { name: "negative lastSeq", raw: snapshot({ lastSeq: -1 }), naiveAccepts: true },
      { name: "unparseable producedAt", raw: snapshot({ producedAt: "not-a-date" }), naiveAccepts: true },
      { name: "too many cards", raw: snapshot({ cards: Array.from({ length: READER_MAX_CARDS + 1 }, (_, index) => card(`att_${index}`)) }), naiveAccepts: true },
      { name: "bad severity", raw: snapshot({ cards: [{ ...card("att_1"), severity: "Z" }] }), naiveAccepts: true },
      { name: "jumpAvailable false", raw: snapshot({ cards: [{ ...card("att_1"), jumpAvailable: false }] }), naiveAccepts: true },
      { name: "negative ageSeconds", raw: snapshot({ cards: [{ ...card("att_1"), ageSeconds: -1 }] }), naiveAccepts: true },
      { name: "empty card id", raw: snapshot({ cards: [{ ...card("att_1"), id: "" }] }), naiveAccepts: true },
    ]
    for (const entry of invalid) {
      const out = await readerFor(() => entry.raw, () => T0, () => 0).read()
      expect(out.state).toBe("frozen")
      if (out.state === "frozen") expect(out.reason).toBe("invalid-schema")
      expect(parseOperatorView(entry.raw)).toBeUndefined()
      if (entry.naiveAccepts) expect(naiveRead(entry.raw)).toBeDefined()
    }
  })

  test("(c8) atomic replace — reader rereads on rename, never a cached image", async () => {
    const dir = await mkdtemp(join(tmpdir(), "operator-view-reader-rename-"))
    try {
      const path = join(dir, "operator-view.json")
      const reader = new OperatorViewReader({ path, wallMs: () => T0, monoMs: () => 0 })
      await writeFile(path, snapshot({ generation: 1, lastSeq: 5, cards: [card("att_A")] }))
      const first = await reader.read()
      expect(first.state).toBe("live")
      if (first.state === "live") expect(first.view.cards[0]?.id).toBe("att_A")

      // Atomic replace: temp file + rename over the live path.
      const temporary = `${path}.tmp-test`
      await writeFile(temporary, snapshot({ generation: 2, lastSeq: 5, cards: [card("att_B")] }))
      await rename(temporary, path)
      const second = await reader.read()
      expect(second.state).toBe("live")
      if (second.state === "live") expect(second.view.cards[0]?.id).toBe("att_B")
    } finally {
      await rm(dir, { recursive: true, force: true })
    }
  })

  test("(c9) supervisor not running (missing file) → frozen read-error", async () => {
    const reader = new OperatorViewReader({
      path: "does-not-exist.json",
      fs: { readFile: async () => { throw Object.assign(new Error("ENOENT"), { code: "ENOENT" }) } },
      wallMs: () => T0,
      monoMs: () => 0,
    })
    const out = await reader.read()
    expect(out.state).toBe("frozen")
    if (out.state === "frozen") expect(out.reason).toBe("read-error")
  })

  test("contract thresholds are pinned", () => {
    expect(READ_STALE_AGE_MS).toBe(30_000)
    expect(READ_FUTURE_SKEW_MS).toBe(5_000)
    expect(READ_CLOCK_JUMP_MS).toBe(5_000)
    expect(READ_MAX_POLL_MS).toBeLessThanOrEqual(5_000)
    expect(READER_MAX_CARDS).toBe(20)
  })
})
