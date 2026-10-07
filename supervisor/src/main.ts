import { runService } from "./service"

const controller = new AbortController()
process.once("SIGTERM", () => controller.abort())
process.once("SIGINT", () => controller.abort())

try {
  await runService(controller.signal)
} catch (error) {
  // no-excuse-ok: catch — process boundary
  console.error(error instanceof Error ? error.message : "unknown supervisor failure")
  // Crash path: nothing to drain gracefully — hard-exit so fire-and-forget
  // loops and keep-alive sockets cannot hold a crashed process alive.
  process.exit(1)
}
