import { expect, test } from "bun:test"
import { ROOT_READY_DEADLINE_MS, startRootPollLoop } from "../src/service"
import restartBlindness from "./fixtures/restart-blindness.json"

test("root loop polls available runtime and drains after abort", async () => {
  // Given
  const controller = new AbortController()
  const calls: string[] = []
  // When
  await startRootPollLoop({
    signal: controller.signal,
    sleep: async () => {},
    getRuntime: () => "runtime",
    poll: async (runtime) => { calls.push(runtime); controller.abort() },
    onError: async () => { throw new Error("unexpected error") },
    onStart: () => { calls.push("start") },
    onStop: () => { calls.push("stop") },
  })
  // Then
  expect(calls).toEqual(["start", "runtime", "stop"])
})

test("Oct 7-8 restart-blindness replay retries reconcile and recovers without restart", async () => {
  // Given: failed boot reconcile left no runtime for the historical 17h10m gap.
  const controller = new AbortController()
  let runtime: string | undefined
  let attempts = 0
  let now = Date.parse(restartBlindness.failedBoot.timestamp)
  let watchdogs = 0
  const polled: string[] = []
  // When
  await startRootPollLoop({
    signal: controller.signal,
    sleep: async () => { now += ROOT_READY_DEADLINE_MS },
    now: () => now,
    getRuntime: () => runtime,
    reconcile: async () => {
      if (++attempts === 3) {
        now = Date.parse(restartBlindness.pollingResumed.timestamp)
        runtime = "recovered"
      }
    },
    onNotReady: async () => { watchdogs += 1 },
    poll: async (value) => { polled.push(value); controller.abort() },
    onError: async () => { throw new Error("unexpected error") },
    onStart: () => {},
    onStop: () => {},
  })
  // Then
  expect(attempts).toBe(3)
  expect(watchdogs).toBe(1)
  expect(polled).toEqual(["recovered"])
})
