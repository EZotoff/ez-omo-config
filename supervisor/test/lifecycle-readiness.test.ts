import { expect, test } from "bun:test"
import { startRootPollLoop } from "../src/service"

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
