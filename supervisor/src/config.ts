import { existsSync } from "node:fs"
import { readFile } from "node:fs/promises"
import { homedir } from "node:os"
import { join } from "node:path"
import { z } from "zod"
import type { AutonomousOriginConfig } from "./origins"

const trustSchema = z.object({
  autonomous_deploy: z.boolean().default(false),
  autonomous_credentialed_actions: z.boolean().default(false),
}).strict().default({ autonomous_deploy: false, autonomous_credentialed_actions: false })
/** Per-root trust: machine-enforced capability flags (config, not ruling). Absent trust = untrusted. */
export type RootTrust = z.infer<typeof trustSchema>
const rootSchema = z.object({
  path: z.string().min(1),
  mode: z.enum(["off", "shadow", "observe", "full"]),
  trust: trustSchema,
  autonomous_path_globs: z.array(z.string().min(1)).default([]),
  continue_writes: z.object({
    enabled: z.boolean().default(false),
    daily_cap: z.number().int().positive().default(5),
    kick_start_only: z.boolean().default(true),
  }).strict().optional(),
  steer_writes: z.object({
    enabled: z.boolean().default(false),
    daily_cap: z.number().int().positive().default(3),
  }).strict().optional(),
  reformulate_writes: z.object({
    enabled: z.boolean().default(false),
    daily_cap: z.number().int().positive().default(3),
  }).strict().optional(),
  approve_writes: z.object({
    enabled: z.boolean().default(false),
    // Absent = uncapped (operator directive 2026-10-05). Present = hard daily limit.
    daily_cap: z.number().int().positive().optional(),
    // Feature Rollout Protocol (2026-10-03 operator decision, Option C):
    // "observe" counts and logs would-grants, grants nothing; "grant" delivers.
    mode: z.enum(["observe", "grant"]).default("observe"),
    // Epoch boundary (Option 2, 2026-10-05): approveWrites counters count only
    // ledger events at/after this timestamp; the tightened POLICY (approve-v1)
    // is in force from here. Would-grant regimes separate by this timestamp.
    epoch_started_at: z.string().datetime().optional(),
  }).strict().optional(),
  autonomous_title_prefixes: z.array(z.string().min(1)).default([]),
}).strict()
const tierBudgetsSchema = z.object({
  target_history: z.number().int().positive(),
  hot: z.number().int().positive(),
  warm: z.number().int().positive(),
  cool: z.number().int().positive(),
  cold: z.number().int().positive(),
}).strict()
const configSchema = z.object({
  server_url: z.string().url(),
  server_username: z.string().min(1).default("opencode"),
  server_password_env: z.string().min(1).default("OPENCODE_SERVER_PASSWORD"),
  initial_window_days: z.number().int().positive().default(1),
  fetch_concurrency: z.number().int().positive().default(8),
  stall_minutes: z.number().int().positive().default(15),
  targeting: z.object({
    adjudicate_machine_origin: z.boolean().default(false),
  }).strict().default({ adjudicate_machine_origin: false }),
  // Error-storm auto-investigation (2026-10-05): when the rolling 1-hour ERROR
  // count reaches `threshold`, create an opencode session asking what is
  // causing the errors. Once per hour window; global (not per-root) because it
  // responds to supervisor-health telemetry, not per-root decisions.
  error_investigation: z.object({
    enabled: z.boolean().default(false),
    threshold: z.number().int().positive().default(10),
    dedup_window_h: z.number().int().positive().default(6),
  }).strict().default({ enabled: false, threshold: 10, dedup_window_h: 6 }),
  // Journal->ledger continuation bridge hygiene (design 2, M4): coalesce
  // repeated continuation alerts by unit|reason, roll suppressed repeats into
  // one per-window digest escalation, and break per-unit escalation storms.
  // coalesce_enabled=false restores legacy one-ESCALATE-per-alert behavior.
  continuation_bridge: z.object({
    coalesce_enabled: z.boolean().default(true),
    coalesce_window_s: z.number().int().positive().default(900),
    max_escalations_per_unit_per_window: z.number().int().positive().default(5),
    cooldown_s: z.number().int().positive().default(3600),
    excluded_units: z.array(z.string().min(1)).default([]),
  }).strict().default({ coalesce_enabled: true, coalesce_window_s: 900, max_escalations_per_unit_per_window: 5, cooldown_s: 3600, excluded_units: [] }),
  model: z.object({ provider: z.string().min(1), id: z.string().min(1) }).strict(),
  grace_period_s: z.number().int().nonnegative(),
  min_intervention_interval_s: z.number().int().nonnegative(),
  max_tick_concurrency: z.number().int().positive(),
  target_history_cap_pairs: z.number().int().positive(),
  sibling_turn_window: z.number().int().positive(),
  token_budget: z.number().int().positive(),
  tier_budgets: tierBudgetsSchema,
  confidence_floor: z.number().min(0).max(1),
  roots: z.array(rootSchema).min(1),
}).strict()

export const supervisorConfigSchema = configSchema
export type SupervisorConfig = z.infer<typeof configSchema>

/** Per-root autonomous-origin detection config (path globs + title prefixes). */
export function rootAutonomousOrigin(root: SupervisorConfig["roots"][number]): AutonomousOriginConfig {
  return { pathGlobs: root.autonomous_path_globs, titlePrefixes: root.autonomous_title_prefixes }
}

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
