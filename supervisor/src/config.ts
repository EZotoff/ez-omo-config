import { existsSync } from "node:fs"
import { readFile } from "node:fs/promises"
import { homedir } from "node:os"
import { join } from "node:path"
import { z } from "zod"

const rootSchema = z.object({ path: z.string().min(1), mode: z.enum(["off", "shadow"]) }).strict()
const configSchema = z.object({
  server_url: z.string().url(),
  server_username: z.string().min(1).default("opencode"),
  server_password_env: z.string().min(1).default("OPENCODE_SERVER_PASSWORD"),
  initial_window_days: z.number().int().positive().default(7),
  fetch_concurrency: z.number().int().positive().default(8),
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
    options: z.record(z.string(), z.unknown()).optional(),
  }).passthrough()),
}).passthrough()

export async function loadProviderBaseURL(opencodePath: string, provider: string): Promise<string> {
  const parsed = providerSchema.parse(JSON.parse(await readFile(opencodePath, "utf8")))
  const entry = parsed.provider[provider]
  const baseURL = entry?.options?.["baseURL"]
  if (typeof baseURL !== "string" || !baseURL.startsWith("http")) {
    throw new ConfigError(`${opencodePath}: provider ${provider} has no options.baseURL`)
  }
  return baseURL
}

const authSchema = z.record(z.string(), z.unknown())

export async function loadApiKey(authPath: string, provider: string): Promise<string> {
  const auth = authSchema.parse(JSON.parse(await readFile(authPath, "utf8")))
  const entry = auth[provider]
  if (typeof entry !== "object" || entry === null) throw new ConfigError(`${authPath}: no entry for ${provider}`)
  const key = (entry as Record<string, unknown>)["key"]
  if (typeof key !== "string" || key.length === 0) {
    throw new ConfigError(`${authPath}: provider ${provider} has no API key (OAuth entries are not supported for tick models)`)
  }
  return key
}
