// Bounded stop-drain (2026-10-07 shutdown hang, ses_ee91cf73 episode):
// runService resolves on abort while fire-and-forget poll loops and keep-alive
// sockets hold the event loop open on a wedged server connection. Attempt 1
// (unref\'d force-exit timer, 0d60c5a) FAILED live: an unref\'d timer does not
// count toward the IO-poll timeout, so with every referenced handle blocked in
// a silent poll the due timer starves indefinitely (journal: SIGTERM 23:27:17,
// manual SIGKILL 23:32:09, no timer fire). The correct primitive is a
// REFERENCED race: drain-completion promise vs a real (referenced) sleep, then
// process.exit(0) on either branch.
import { describe, expect, test } from "bun:test"
import { boundedDrain, STOP_DRAIN_GRACE_MS } from "../src/stop-drain"

describe("boundedDrain", () => {
  test("resolves \'drained\' immediately when the drain promise wins", async () => {
    const outcome = await boundedDrain(Promise.resolve("drained"), 5_000)
    expect(outcome).toBe("drained")
  })
  test("resolves \'deadline\' when the drain never completes (wedged in-flight call)", async () => {
    const never = new Promise<"drained">(() => {})
    const t0 = Date.now()
    const outcome = await boundedDrain(never, 40)
    expect(outcome).toBe("deadline")
    expect(Date.now() - t0).toBeLessThan(2_000)
  })
  test("default budget stays inside systemd\'s 5-min stop timeout with margin above the ~60-72s normal drain", () => {
    expect(STOP_DRAIN_GRACE_MS).toBe(120_000)
    expect(STOP_DRAIN_GRACE_MS).toBeLessThan(300_000)
  })
})
