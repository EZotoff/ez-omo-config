import { describe, expect, test } from "bun:test"
import { mkdtemp, readFile, readdir, rm } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"
import {
  MAX_CARDS,
  OPERATOR_VIEW_HEARTBEAT_MS,
  OperatorViewPublisher,
  buildOperatorView,
  isProbeItem,
} from "../src/operator-view"
import type { AttentionQueueItem } from "../src/types"
import { T0, fixtureItem } from "./helpers"

const readView = async (path: string) => JSON.parse(await readFile(path, "utf8")) as {
  schemaVersion: number
  generation: number
  lastSeq: number
  producedAt: string
  cards: Array<{ id: string; rootLabel: string; sessionLabel: string; reasonText: string; premiseTexts: string[]; ageSeconds: number; severity: string; jumpAvailable: boolean }>
}

let sequence = 0
const nextID = (): `att_${string}` => {
  sequence += 1
  return `att_test${sequence.toString().padStart(4, "0")}`
}

describe("operator-view acceptance", () => {
  test("(1) published file has generation/lastSeq/producedAt and bounded cards", async () => {
    const dir = await mkdtemp(join(tmpdir(), "operator-view-shape-"))
    try {
      const items = [fixtureItem({ id: nextID() })]
      const publisher = new OperatorViewPublisher({ path: join(dir, "operator-view.json"), items: () => items, ledgerSeq: () => 7, nowMs: () => T0 })
      const view = await publisher.publish()
      expect(view.schemaVersion).toBe(1)
      expect(view.generation).toBe(1)
      expect(view.lastSeq).toBe(5)
      expect(view.producedAt).toBe("2026-09-23T12:00:00.000Z")
      expect(view.cards.length).toBe(1)
      const card = view.cards[0]!
      expect(card.rootLabel).toBe("proj")
      expect(card.reasonText).toBe("Deploy to prod?")
      expect(["A", "B", "C", "D"]).toContain(card.severity)
      expect(card.jumpAvailable).toBe(true)
      // no temp residue matching any discovery glob
      expect((await readdir(dir)).filter((name) => name !== "operator-view.json")).toEqual([])
    } finally {
      await rm(dir, { recursive: true, force: true })
    }
  })

  test("(2) atomicity — concurrent reader never observes a torn image", async () => {
    const dir = await mkdtemp(join(tmpdir(), "operator-view-atomic-"))
    try {
      const path = join(dir, "operator-view.json")
      const publisher = new OperatorViewPublisher({ path, items: () => items, ledgerSeq: () => 50, nowMs: () => T0 })
      const items = Array.from({ length: 40 }, (_, index) => fixtureItem({ id: nextID(), origin: { ...fixtureItem().origin, ledgerSeq: index + 1 } }))
      let torn = 0
      let reads = 0
      let stop = false
      const reader = (async () => {
        while (!stop) {
          try {
            const raw = await readFile(path, "utf8")
            reads += 1
            const parsed = JSON.parse(raw)
            if (typeof parsed.generation !== "number" || !Array.isArray(parsed.cards)) torn += 1
          } catch (error) {
            if ((error as NodeJS.ErrnoException).code !== "ENOENT") torn += 1
          }
        }
      })()
      for (let round = 0; round < 30; round += 1) await publisher.publish()
      stop = true
      await reader
      expect(reads).toBeGreaterThan(0)
      expect(torn).toBe(0)
    } finally {
      await rm(dir, { recursive: true, force: true })
    }
  })

  test("(3) lastSeq never exceeds incorporated card data", async () => {
    const dir = await mkdtemp(join(tmpdir(), "operator-view-seq-"))
    try {
      const path = join(dir, "operator-view.json")
      // Ledger has 100 records; the queue item entered at seq 5 — never publish the tail.
      const publisher = new OperatorViewPublisher({ path, items: () => [fixtureItem({ id: nextID() })], ledgerSeq: () => 100, nowMs: () => T0 })
      await publisher.publish()
      const view = await readView(path)
      expect(view.lastSeq).toBe(5)
      // Monotonic across republishes; still bounded by the ledger observed.
      await publisher.publish()
      const again = await readView(path)
      expect(again.generation).toBe(2)
      expect(again.lastSeq).toBe(5)
    } finally {
      await rm(dir, { recursive: true, force: true })
    }
  })

  test("(4) heartbeat republishes with fresh producedAt when the ledger is idle", async () => {
    const dir = await mkdtemp(join(tmpdir(), "operator-view-heartbeat-"))
    try {
      const path = join(dir, "operator-view.json")
      const items = [fixtureItem({ id: nextID() })]
      let clock = T0
      const publisher = new OperatorViewPublisher({ path, items: () => items, ledgerSeq: () => 5, nowMs: () => clock })
      const first = await publisher.publish()
      // Simulated ≥30 s of no ledger change: heartbeat keeps republishing.
      clock += 35_000
      publisher.startHeartbeat(10)
      await Bun.sleep(60)
      publisher.stop()
      const view = await readView(path)
      expect(view.generation).toBeGreaterThan(first.generation)
      expect(Date.parse(view.producedAt)).toBeGreaterThan(Date.parse(first.producedAt))
      expect(view.cards.map((card) => card.id)).toEqual(first.cards.map((card) => card.id))
    } finally {
      await rm(dir, { recursive: true, force: true })
    }
  })

  test("(5) probe-noise — a probe-class burst adds/displaces zero cards", async () => {
    const real = [fixtureItem({ id: nextID() }), fixtureItem({ id: nextID() })]
    const probeBurst: AttentionQueueItem[] = Array.from({ length: 25 }, () =>
      fixtureItem({
        id: nextID(),
        target: { root: "/home/user/proj", sessionID: "ses-probe", userMessageID: "m", sessionTitle: "PROBE-OK" },
        priority: { stakes: 5, urgency: 5, confidence: 1, freshness: 1, createdAt: "2026-09-23T11:59:00.000Z" },
      }))
    expect(isProbeItem(probeBurst[0]!)).toBe(true)
    const without = buildOperatorView({ items: real, ledgerSeq: 10, generation: 1, nowMs: T0 })
    const withBurst = buildOperatorView({ items: [...real, ...probeBurst], ledgerSeq: 35, generation: 2, nowMs: T0 })
    expect(withBurst.view.cards.map((card) => card.id)).toEqual(without.view.cards.map((card) => card.id))
    // Probe items contribute no lastSeq either.
    expect(withBurst.view.lastSeq).toBe(without.view.lastSeq)
  })

  test("(6) quiet period — 10 simulated minutes, cards stay live (fresh producedAt), never grey", async () => {
    const dir = await mkdtemp(join(tmpdir(), "operator-view-quiet-"))
    try {
      const path = join(dir, "operator-view.json")
      const items = [fixtureItem({ id: nextID() })]
      let clock = T0
      const publisher = new OperatorViewPublisher({ path, items: () => items, ledgerSeq: () => 5, nowMs: () => clock })
      await publisher.publish()
      // 10 simulated minutes of no escalations; heartbeat (compressed to 60 s
      // simulated per tick) keeps producedAt within the 30 s staleness budget
      // at every simulated receipt point.
      publisher.startHeartbeat(5)
      for (let minute = 1; minute <= 10; minute += 1) {
        clock += 60_000
        // Bounded wait for the heartbeat publish carrying THIS simulated instant.
        const deadline = Date.now() + 2_000
        let fresh = await readView(path)
        while (Date.parse(fresh.producedAt) < clock && Date.now() < deadline) {
          await Bun.sleep(5)
          fresh = await readView(path)
        }
        expect(Date.parse(fresh.producedAt)).toBe(clock)
        expect(clock - Date.parse(fresh.producedAt)).toBeLessThan(30_000)
        expect(fresh.cards.length).toBe(1)
      }
      publisher.stop()
    } finally {
      await rm(dir, { recursive: true, force: true })
    }
  })

  test("caps: card count and text fields are bounded", () => {
    const many = Array.from({ length: MAX_CARDS + 30 }, () =>
      fixtureItem({
        id: nextID(),
        question: "x".repeat(5000),
        premises: Array.from({ length: 9 }, (_, index) => ({ id: `p${index}`, kind: "no-newer-turn" as const, sessionID: "ses-a", latestMessageID: "m".repeat(300), observedAt: "2026-09-23T11:59:00.000Z" })),
      }))
    const { view } = buildOperatorView({ items: many, ledgerSeq: 100, generation: 1, nowMs: T0 })
    expect(view.cards.length).toBeLessThanOrEqual(MAX_CARDS)
    for (const card of view.cards) {
      expect(card.reasonText.length).toBeLessThanOrEqual(200)
      expect(card.premiseTexts.length).toBeLessThanOrEqual(5)
      for (const text of card.premiseTexts) expect(text.length).toBeLessThanOrEqual(160)
    }
  })

  test("default heartbeat interval satisfies the ≤15 s contract obligation", () => {
    expect(OPERATOR_VIEW_HEARTBEAT_MS).toBeLessThanOrEqual(15_000)
  })
})
