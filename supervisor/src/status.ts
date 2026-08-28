import { mkdir, open, readFile, rename } from "node:fs/promises"
import { dirname } from "node:path"
import { z } from "zod"

export const statusSchema = z.object({
  lastReconcile: z.string().nullable(),
  queueDepths: z.record(z.string(), z.number().int().nonnegative()),
  ticksByAction: z.record(z.string(), z.number().int().nonnegative()),
  unknownOriginRate: z.number().min(0).max(1),
}).strict()
export type SupervisorStatus = z.infer<typeof statusSchema>

export async function writeStatus(path: string, status: SupervisorStatus): Promise<void> {
  await mkdir(dirname(path), { recursive: true })
  const temporary = `${path}.tmp-${process.pid}`
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
