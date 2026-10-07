import { runService } from "./service"
import { armStopDrainDeadline } from "./stop-drain"

const controller = new AbortController()
process.once("SIGTERM", () => controller.abort())
process.once("SIGINT", () => controller.abort())

try {
  await runService(controller.signal)
} catch (error) {
  // no-excuse-ok: catch — process boundary
  console.error(error instanceof Error ? error.message : "unknown supervisor failure")
  process.exitCode = 1
}
// Reached only when runService resolved (SIGTERM/SIGINT shutdown) or crashed.
// Bounded drain (2026-10-07 shutdown hang): per-root poll loops and keep-alive
// sockets can hold the event loop past systemd's stop timeout on a wedged
// connection — the unref'd deadline force-exits at 120s while letting a clean
// drain exit naturally and faster.
armStopDrainDeadline()
