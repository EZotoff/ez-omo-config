import { randomUUID } from "node:crypto"
import { mkdir, open, readFile, rename } from "node:fs/promises"
import { dirname } from "node:path"
import { z } from "zod"

const collectTelemetrySchema = z.object({
  attempts: z.number().int().nonnegative(),
  performed: z.number().int().nonnegative(),
  changed: z.number().int().nonnegative(),
  discarded: z.number().int().nonnegative(),
  budgetExhausted: z.number().int().nonnegative(),
  tokens: z.number().int().nonnegative(),
  rate: z.number().min(0).max(1),
  changedRate: z.number().min(0).max(1),
}).strict()

export const statusSchema = z.object({
  lastReconcile: z.string().nullable(),
  queueDepths: z.record(z.string(), z.number().int().nonnegative()),
  ticksByAction: z.record(z.string(), z.number().int().nonnegative()),
  unknownOriginRate: z.number().min(0).max(1),
  modes: z.record(z.string(), z.string()).optional(),
  errorsSinceStart: z.number().int().nonnegative().optional(),
  errorsLastHour: z.number().int().nonnegative().optional(),
  errorsLastHourPeak: z.number().int().nonnegative().optional(),
  errorInvestigations: z.number().int().nonnegative().optional(),
  rootHealth: z.record(z.string(), z.object({
    state: z.enum(["ok", "failing"]),
    consecutiveFailures: z.number().int().nonnegative(),
    lastErrorAt: z.string().optional(),
  })).optional(),
  machineMarkedRate: z.number().min(0).max(1),
  actionFunnel: z.record(z.string(), z.object({
    decided: z.number().int().nonnegative(),
    effect: z.number().int().nonnegative(),
    skipped: z.number().int().nonnegative(),
  }).strict()).optional(),
  approveWrites: z.object({
    wouldGrant: z.number().int().nonnegative(),
    granted: z.number().int().nonnegative(),
    skipped: z.number().int().nonnegative(),
  }).strict().optional(),
  collect: collectTelemetrySchema.optional(),
  /** Sessions blocked on the operator's question-tool dialog (2026-10-05 awaiting-operator-input guard). */
  awaitingOperator: z.object({
    count: z.number().int().nonnegative(),
    oldestQuestionStartMs: z.number().int().nonnegative().optional(),
  }).strict().optional(),
}).strict()
export type SupervisorStatus = z.infer<typeof statusSchema>
export type CollectTelemetry = z.infer<typeof collectTelemetrySchema>

export async function writeStatus(path: string, status: SupervisorStatus): Promise<void> {
  await mkdir(dirname(path), { recursive: true })
  const temporary = `${path}.tmp-${process.pid}-${randomUUID()}`
  const handle = await open(temporary, "w", 0o600)
  try {
    await handle.writeFile(`${JSON.stringify(status, null, 2)}\n`)
    await handle.sync()
  } finally {
    await handle.close()
  }
  await rename(temporary, path)
}

export async function readStatus(path: string): Promise<SupervisorStatus> {
  return statusSchema.parse(JSON.parse(await readFile(path, "utf8")))
}
