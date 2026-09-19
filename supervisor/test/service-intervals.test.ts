import { describe, expect, test } from "bun:test"
import { SessionScheduler } from "../src/service"

const INTERVAL_MS = 300_000

function makeScheduler() {
  let now = 1_000_000
  const started: string[] = []
  const finished: string[] = []
  const pending: Array<() => void> = []
  const scheduler = new SessionScheduler(INTERVAL_MS, () => now, async (sessionID) => {
    started.push(sessionID)
    await new Promise<void>((resolve) => pending.push(resolve))
    finished.push(sessionID)
  })
  return {
    scheduler,
    started,
    finished,
    advance: (ms: number) => { now += ms },
    settleAll: () => { for (const resolve of pending.splice(0)) resolve() },
  }
}

const flush = async (): Promise<void> => {
  for (let i = 0; i < 5; i += 1) await Promise.resolve()
}

describe("SessionScheduler", () => {
  test("two sessions idle in same root both tick within one interval window", async () => {
    const harness = makeScheduler()
    void harness.scheduler.enqueue("s1").catch(() => {})
    void harness.scheduler.enqueue("s2").catch(() => {})
    await flush()
    // Both dispatch concurrently — neither waits for the other's grace/tick.
    expect(harness.started).toEqual(["s1", "s2"])
    expect(harness.finished).toEqual([])
  })

  test("interval is respected per session, not per root", async () => {
    const harness = makeScheduler()
    harness.scheduler.markTicked("s1")
    harness.advance(100_000) // inside s1's interval, but s2 never ticked

    void harness.scheduler.enqueue("s2").catch(() => {})
    await flush()
    expect(harness.started).toEqual(["s2"]) // root NOT muted by s1's tick

    void harness.scheduler.enqueue("s1").catch(() => {})
    await flush()
    expect(harness.started).toEqual(["s2"]) // s1 throttled inside the interval

    harness.advance(201_000) // now past s1's interval (100k + 201k > 300k)
    void harness.scheduler.enqueue("s1").catch(() => {})
    await flush()
    expect(harness.started).toEqual(["s2", "s1"])
  })

  test("work for the same session is serialized", async () => {
    const harness = makeScheduler()
    void harness.scheduler.enqueue("s1").catch(() => {})
    await flush()
    void harness.scheduler.enqueue("s1").catch(() => {})
    await flush()
    expect(harness.started).toEqual(["s1"]) // second waits for first

    harness.settleAll()
    await flush()
    expect(harness.started).toEqual(["s1", "s1"])
    expect(harness.finished).toEqual(["s1"])
  })

  test("a failed run does not poison later ticks for the session", async () => {
    let now = 1_000_000
    const scheduler = new SessionScheduler(INTERVAL_MS, () => now, async () => {
      throw new Error("boom")
    })
    void scheduler.enqueue("s1").catch(() => {})
    for (let i = 0; i < 5; i += 1) await Promise.resolve()
    now += INTERVAL_MS + 1
    const second = scheduler.enqueue("s1")
    await expect(second).rejects.toThrow("boom")
    // Chain self-heals: a third enqueue reaches the run callback.
    now += INTERVAL_MS + 1
    const third = scheduler.enqueue("s1")
    await expect(third).rejects.toThrow("boom")
  })
})
