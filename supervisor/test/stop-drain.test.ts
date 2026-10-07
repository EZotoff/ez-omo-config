// Bounded stop-drain deadline (2026-10-07 shutdown hang): runService resolves
// on abort while fire-and-forget poll loops and keep-alive sockets can hold
// the event loop open indefinitely on a wedged server connection — observed
// live as an ep_poll stall past systemd's 5-min TimeoutStopUSec, SIGKILL
// required. The deadline is an UNREF'D timer: it never keeps the process
// alive (a clean drain still exits naturally, faster), but fires if a wedged
// in-flight call would otherwise hold the process past the budget.
import { describe, expect, test } from "bun:test"
import { armStopDrainDeadline, STOP_DRAIN_GRACE_MS } from "../src/stop-drain"

describe("armStopDrainDeadline", () => {
  test("force-exits with code 0 and a diagnostic after the grace elapses", async () => {
    const calls: { error: string[]; exit: number[] } = { error: [], exit: [] }
    armStopDrainDeadline(30, {
      error: (msg) => calls.error.push(msg),
      exit: (code) => { calls.exit.push(code) },
    })
    await Bun.sleep(120)
    expect(calls.exit).toEqual([0])
    expect(calls.error[0]).toContain("force exit")
    expect(calls.error[0]).toContain("30") // the armed budget is named in the diagnostic
  })
  test("armed timer never keeps the event loop alive (unref'd)", () => {
    const timer = armStopDrainDeadline(60_000, { error: () => {}, exit: () => {} })
    expect(typeof timer.unref).toBe("function")
    expect(timer.hasRef()).toBe(false)
    clearTimeout(timer)
  })
  test("default budget stays inside systemd's 5-min stop timeout with margin", () => {
    expect(STOP_DRAIN_GRACE_MS).toBe(120_000)
    expect(STOP_DRAIN_GRACE_MS).toBeLessThan(300_000)
  })
})
