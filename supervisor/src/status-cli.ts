import { homedir } from "node:os"
import { join } from "node:path"
import { Ledger } from "./ledger"
import { ProtectionRegistry } from "./protect"
import { readStatus } from "./status"

const stateDirectory = process.env["OPENCODE_SUPERVISOR_STATE_DIR"] ?? join(homedir(), ".local", "state", "opencode-supervisor")

const USAGE = "usage: status-cli.ts [protect <sessionID> [--reason <text...>] | unprotect <sessionID>]"

try {
  const [command, ...args] = process.argv.slice(2)

  if (command === "protect" || command === "unprotect") {
    const reasonIndex = args.indexOf("--reason")
    const reason = reasonIndex === -1 ? undefined : args.slice(reasonIndex + 1).join(" ") || undefined
    const sessionID = args.slice(0, reasonIndex === -1 ? args.length : reasonIndex).find((arg) => arg !== "")
    if (sessionID === undefined) {
      console.error(USAGE)
      process.exitCode = 1
    } else {
      const registry = await ProtectionRegistry.open(join(stateDirectory, "protected.json"))
      if (command === "protect") {
        const entry = await registry.protect(sessionID, reason === undefined ? {} : { reason })
        console.log(`protected ${entry.sessionID}${entry.reason === undefined ? "" : ` (${entry.reason})`} since ${entry.since}`)
      } else {
        const removed = await registry.unprotect(sessionID)
        console.log(removed ? `unprotected ${sessionID}` : `${sessionID} was not protected`)
      }
    }
  } else {
    const status = await readStatus(join(stateDirectory, "status.json"))
    const ledger = await Ledger.open(join(stateDirectory, "ledger.jsonl"))
    const decisions = ledger.records.filter((record) => record.type === "TICK_DECIDED").slice(-10)
    const registry = await ProtectionRegistry.open(join(stateDirectory, "protected.json"))
    console.log(`Last reconcile: ${status.lastReconcile ?? "never"}`)
    console.log(`Queue depths: ${JSON.stringify(status.queueDepths)}`)
    console.log(`Ticks by action: ${JSON.stringify(status.ticksByAction)}`)
    console.log(`Unknown-origin rate: ${(status.unknownOriginRate * 100).toFixed(2)}%`)
    console.log(`Protected sessions: ${registry.entries.map((entry) => entry.sessionID).join(", ") || "none"}`)
    console.log(`Recent decisions: ${decisions.length}`)
    for (const record of decisions) console.log(`#${record.seq} ${record.timestamp} ${JSON.stringify(record.payload)}`)
  }
} catch (error) {
  // no-excuse-ok: catch — CLI boundary
  console.error(error instanceof Error ? error.message : "unable to read supervisor status")
  process.exitCode = 1
}
