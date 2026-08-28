import { existsSync } from "node:fs"
import { readFile } from "node:fs/promises"
import { homedir } from "node:os"
import { join } from "node:path"
import { z } from "zod"

const rootSchema = z.object({ path: z.string().min(1), mode: z.enum(["off", "shadow"]) }).strict()
const configSchema = z.object({
  server_url: z.string().url(),
  model: z.object({ provider: z.string().min(1), id: z.string().min(1) }).strict(),
  grace_period_s: z.number().int().nonnegative(),
  min_intervention_interval_s: z.number().int().nonnegative(),
  max_tick_concurrency: z.number().int().positive(),
  target_history_cap_pairs: z.number().int().positive(),
  sibling_turn_window: z.number().int().positive(),
  token_budget: z.number().int().positive(),
  confidence_floor: z.number().min(0).max(1),
  roots: z.array(rootSchema).min(1),
}).strict()

export type SupervisorConfig = z.infer<typeof configSchema>

export class ConfigError extends Error {
  readonly name = "ConfigError"
  constructor(readonly path: string, options?: ErrorOptions) {
    super(`invalid supervisor config: ${path}`, options)
  }
}

export async function loadConfig(bundledPath: string): Promise<SupervisorConfig> {
  const runtimePath = join(homedir(), ".config", "opencode-supervisor", "supervisor.json")
  const path = existsSync(runtimePath) ? runtimePath : bundledPath
  try {
    return configSchema.parse(JSON.parse(await readFile(path, "utf8")))
  } catch (error) {
    if (error instanceof Error) throw new ConfigError(path, { cause: error })
    throw error
  }
}

const providerSchema = z.object({
  provider: z.record(z.string(), z.object({
    options: z.object({ baseURL: z.string().url() }).passthrough(),
  }).passthrough()),
}).passthrough()

export async function loadProviderBaseURL(opencodePath: string, provider: string): Promise<string> {
  const parsed = providerSchema.parse(JSON.parse(await readFile(opencodePath, "utf8")))
  const entry = parsed.provider[provider]
  if (entry === undefined) throw new ConfigError(opencodePath)
  return entry.options.baseURL
}

const authSchema = z.record(z.string(), z.object({ type: z.literal("api"), key: z.string().min(1) }).strict())

export async function loadApiKey(authPath: string, provider: string): Promise<string> {
  const auth = authSchema.parse(JSON.parse(await readFile(authPath, "utf8")))
  const entry = auth[provider]
  if (entry === undefined) throw new ConfigError(authPath)
  return entry.key
}
