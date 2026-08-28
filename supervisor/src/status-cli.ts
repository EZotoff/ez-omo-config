import { homedir } from "node:os"
import { join } from "node:path"
import { Ledger } from "./ledger"
import { readStatus } from "./status"

const stateDirectory = process.env["OPENCODE_SUPERVISOR_STATE_DIR"] ?? join(homedir(), ".local", "state", "opencode-supervisor")

try {
  const status = await readStatus(join(stateDirectory, "status.json"))
  const ledger = await Ledger.open(join(stateDirectory, "ledger.jsonl"))
  const decisions = ledger.records.filter((record) => record.type === "TICK_DECIDED").slice(-10)
  console.log(`Last reconcile: ${status.lastReconcile ?? "never"}`)
  console.log(`Queue depths: ${JSON.stringify(status.queueDepths)}`)
  console.log(`Ticks by action: ${JSON.stringify(status.ticksByAction)}`)
  console.log(`Unknown-origin rate: ${(status.unknownOriginRate * 100).toFixed(2)}%`)
  console.log(`Recent decisions: ${decisions.length}`)
  for (const record of decisions) console.log(`#${record.seq} ${record.timestamp} ${JSON.stringify(record.payload)}`)
} catch (error) {
  // no-excuse-ok: catch — CLI boundary
  console.error(error instanceof Error ? error.message : "unable to read supervisor status")
  process.exitCode = 1
}
