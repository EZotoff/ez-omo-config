// Bounded stop-drain deadline (2026-10-07 shutdown hang, ses_ee91cf73 episode):
// runService resolves on abort while the per-root poll loops (fire-and-forget)
// and keep-alive sockets to the opencode server can hold the event loop open
// indefinitely on a wedged connection — observed live as an ep_poll stall past
// systemd's 5-min TimeoutStopUSec, SIGKILL required (pre-merge stop: ~60s).
// The deadline timer is UNREF'D: it never keeps the process alive (a clean
// drain exits naturally, faster), but fires if a wedged in-flight client call
// would otherwise hold the process hostage. Budget must stay well inside the
// unit's TimeoutStopUSec (300s) with margin above the observed normal drain
// (~60-72s).

/** Hard-exit budget after SIGTERM, in ms. */
export const STOP_DRAIN_GRACE_MS = 120_000

export type StopDrainIO = {
  readonly error: (message: string) => void
  readonly exit: (code: number) => void
}

/**
 * Arm the force-exit deadline. Call ONCE, after `runService` has resolved
 * (i.e. only on the abort/shutdown path) — arming at startup would kill a
 * healthy long-running service. Returns the timer for tests.
 */
export function armStopDrainDeadline(
  graceMs: number = STOP_DRAIN_GRACE_MS,
  io: StopDrainIO = { error: (message) => console.error(message), exit: (code) => process.exit(code) },
): Timer {
  const timer = setTimeout(() => {
    io.error(`[supervisor] stop drain exceeded ${graceMs}ms — force exit (wedged in-flight client call holds the event loop; pending fetches are dropped, ledger writes are fs-complete)`)
    io.exit(0)
  }, graceMs)
  timer.unref?.()
  return timer
}
