import { runService } from "./service"

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
