// Bounded stop-drain (2026-10-07 shutdown hang, ses_ee91cf73 episode):
// runService resolves on abort while the per-root poll loops (fire-and-forget)
// and keep-alive sockets to the opencode server can hold the event loop open
// indefinitely on a wedged connection — observed live as an ep_poll stall past
// systemd\'s 5-min TimeoutStopUSec, SIGKILL required (pre-merge stop: ~60s).
//
// Attempt 1 (0d60c5a: unref\'d force-exit timer) FAILED live — an unref\'d timer
// does not count toward the IO-poll timeout, so when every referenced handle
// is blocked in a silent poll the due timer starves until an IO event arrives
// (journal: SIGTERM 23:27:17, no fire, manual SIGKILL 23:32:09). The correct
// primitive is a REFERENCED race: the drain-completion promise vs a real
// Bun.sleep (referenced -> bounds the poll timeout -> always fires on time),
// with process.exit(0) on either branch. Clean drains still exit at their own
// pace (observed ~60-72s); wedged ones are cut at the deadline.

/** Hard-exit budget after SIGTERM, in ms. */
export const STOP_DRAIN_GRACE_MS = 120_000

/**
 * Race the drain-completion promise against a referenced deadline sleep.
 * Resolves "drained" when the drain wins, "deadline" when the budget elapses —
 * the caller then force-exits (process.exit) so wedged fetches cannot hold the
 * process past the unit\'s stop timeout.
 */
export async function boundedDrain(
  drain: Promise<"drained">,
  graceMs: number = STOP_DRAIN_GRACE_MS,
): Promise<"drained" | "deadline"> {
  return Promise.race([drain, Bun.sleep(graceMs).then(() => "deadline" as const)])
}
