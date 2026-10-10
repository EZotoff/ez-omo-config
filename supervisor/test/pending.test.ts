import { afterEach, expect, test } from "bun:test"
import { mkdtemp, rm } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { PendingAttentionStore } from "../src/pending"
import { SessionScheduler } from "../src/service"

const directories: string[] = []
afterEach(async () => { await Promise.all(directories.splice(0).map((path) => rm(path, { recursive: true, force: true }))) })
async function fixture() {
  const directory = await mkdtemp(join(tmpdir(), "pending-attention-"))
  directories.push(directory)
  const clock = { now: 0 }
  const deps = { path: join(directory, "pending.json"), now: () => clock.now, maxAttempts: 4, backoffS: [120, 300, 900, 1800] }
  return { clock, deps, store: await PendingAttentionStore.open(deps) }
}
const skip = { root: "/project", sessionID: "s", reason: "missing-context" as const }

test("record persists only retryable skips and never resets an open episode", async () => {
  const { store, clock } = await fixture()
  for (const reason of ["stale-target", "aborted", "protected"] as const) await store.record({ ...skip, reason })
  expect(store.records).toHaveLength(0)
  await store.record(skip)
  clock.now = 1_000
  await store.record(skip)
  expect(store.records).toMatchObject([{ createdAt: 0, attempts: 0, nextAttemptAt: 120_000, disposition: "open" }])
})

test("injected clock drives the four backoffs and exhausted disposition", async () => {
  const { store, clock } = await fixture()
  await store.record(skip)
  for (const [index, at] of [120_000, 420_000, 1_320_000, 3_120_000].entries()) {
    clock.now = at - 1
    expect(store.due()).toHaveLength(0)
    clock.now = at
    expect(store.due()).toHaveLength(1)
    await store.beginAttempt(skip)
    await store.record(skip)
    expect(store.records[0]?.attempts).toBe(index + 1)
  }
  expect(store.records[0]?.disposition).toBe("exhausted")
  expect(store.due()).toHaveLength(0)
  await store.record(skip)
  expect(store.records[0]?.disposition).toBe("exhausted")
})

test("boot reload re-arms due records and preserves resolved records", async () => {
  const { store, clock, deps } = await fixture()
  await store.record({ ...skip, targetUserMessageID: "u1" })
  clock.now = 120_000
  const restarted = await PendingAttentionStore.open(deps)
  expect(restarted.due()).toMatchObject([{ targetUserMessageID: "u1", disposition: "open" }])
  await restarted.resolve(skip)
  expect((await PendingAttentionStore.open(deps)).records[0]?.disposition).toBe("resolved")
})

test("an interrupted final retry cannot exceed the hard cap after restart", async () => {
  const { store, clock, deps } = await fixture()
  await store.record(skip)
  for (let attempt = 0; attempt < 4; attempt += 1) {
    clock.now = store.records[0]?.nextAttemptAt ?? 0
    await store.beginAttempt(skip)
  }
  const restarted = await PendingAttentionStore.open(deps)
  clock.now = restarted.records[0]?.nextAttemptAt ?? 0
  await restarted.beginAttempt(skip)
  expect(restarted.records[0]).toMatchObject({ attempts: 4, disposition: "exhausted" })
})

test("retry and poll serialize on the same scheduler and consume one due attempt", async () => {
  const { store, clock } = await fixture()
  await store.record(skip)
  clock.now = 120_000
  let calls = 0
  const scheduler = new SessionScheduler(300_000, () => clock.now, async () => { calls += 1; scheduler.markTicked("s"); await store.resolve(skip) })
  const retry = () => scheduler.enqueueRetry("s", async () => { await store.beginAttempt(skip); return true })
  await Promise.all([retry(), retry()])
  expect(calls).toBe(1)
  expect(store.records[0]).toMatchObject({ attempts: 1, disposition: "resolved" })
})
