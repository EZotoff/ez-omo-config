import { describe, expect, test } from "bun:test"
import { supervisorConfigSchema, type RootTrust } from "../src/config"
import { assembleContext, type AssembleInput } from "../src/assembler"
import type { Turn } from "../src/types"

const turn = (user: string, assistant: string): Turn => ({
  sessionID: "ses_trust",
  userMessageID: "u1",
  assistantMessageID: "a1",
  origin: "human",
  userText: user,
  assistantText: assistant,
  transcript: `USER: ${user}\nASSISTANT: ${assistant}`,
})

const assemble = (rootTrust?: RootTrust): string => {
  const input: AssembleInput = {
    target: turn("Should I deploy this to prod now?", "I have prepared the release; awaiting confirmation to deploy."),
    targetHistory: [],
    targetHistoryCapPairs: 50,
    siblingTurnWindow: 3,
    tokenBudget: 40000,
    ...(rootTrust === undefined ? {} : { rootTrust }),
  }
  return assembleContext(input).text
}

const baseConfig = (roots: unknown[]) => JSON.stringify({
  server_url: "http://127.0.0.1:3021",
  model: { provider: "p", id: "m" },
  grace_period_s: 60,
  min_intervention_interval_s: 300,
  max_tick_concurrency: 4,
  target_history_cap_pairs: 50,
  sibling_turn_window: 3,
  token_budget: 40000,
  tier_budgets: { target_history: 15000, hot: 8000, warm: 6000, cool: 4000, cold: 2000 },
  confidence_floor: 0.6,
  roots,
})

const parse = (roots: unknown[]) => supervisorConfigSchema.safeParse(JSON.parse(baseConfig(roots)))

describe("per-root trust config", () => {
  test("missing trust block defaults to untrusted (fail-closed)", () => {
    const result = parse([{ path: "/tmp/opencode/proj", mode: "observe" }])
    if (!result.success) throw new Error("fixture config should parse")
    const root = result.data.roots[0]
    if (root === undefined) throw new Error("fixture root missing")
    expect(root.trust.autonomous_deploy).toBe(false)
    expect(root.trust.autonomous_credentialed_actions).toBe(false)
  })

  test("invalid trust values fail closed (schema rejects)", () => {
    const result = parse([{ path: "/tmp/opencode/proj", mode: "observe", trust: { autonomous_deploy: "yes" } }])
    expect(result.success).toBe(false)
  })

  test("D302 shape without trust: deploy question context carries UNTRUSTED line", () => {
    const text = assemble(undefined)
    expect(text).toContain("ROOT TRUST: autonomous_deploy=false; autonomous_credentialed_actions=false")
    expect(text).toContain("deploy")
  })

  test("trusted root context carries trusted flags", () => {
    const text = assemble({ autonomous_deploy: true, autonomous_credentialed_actions: false })
    expect(text).toContain("ROOT TRUST: autonomous_deploy=true; autonomous_credentialed_actions=false")
  })

  test("ROOT TRUST line present with both flags trusted", () => {
    const text = assemble({ autonomous_deploy: true, autonomous_credentialed_actions: true })
    expect(text).toContain("ROOT TRUST: autonomous_deploy=true; autonomous_credentialed_actions=true")
  })
})
