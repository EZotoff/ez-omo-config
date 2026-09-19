import { describe, expect, test } from "bun:test"
import {
  AUTONOMOUS_ORIGIN_LABEL,
  classifyAutonomousOrigin,
  globToRegExp,
  matchesAstraKickoff,
  type AutonomousOriginConfig,
} from "../src/origins"
import { autonomousSessionIDs } from "../src/topology"
import { assembleContext, type AssembleInput, type AssembledContext, type SiblingView } from "../src/assembler"
import {
  applyAutonomousOriginPolicy,
  isCredentialBlocker,
  POLICY,
  runTickWithCollect,
  type CollectForkRequest,
  type TickDecision,
} from "../src/tick"
import { rootAutonomousOrigin, supervisorConfigSchema } from "../src/config"
import type { ReasoningAdapter } from "../src/adapter"
import type { Session, Turn } from "../src/types"

// D073 fixture (operator ruling 2026-09-18): a bench-runner judge session,
// machine-initiated, no human owner — "taken to their logical end without any
// of my involvement". Directory + title are verbatim from the grading corpus.
const D073 = {
  directory: "ez-omo-bench/benchmarks/writing/runs/writing-glm53flash-20260901/cases/qa-charter/judge",
  title: "bench-judge:qa-charter",
  sessionID: "ses_f8e9c8cc7ffe5vj4",
} as const

const benchConfig: AutonomousOriginConfig = {
  pathGlobs: ["**/benchmarks/**/runs/**"],
  titlePrefixes: ["bench-judge:", "ASTRA Night"],
}

const target: Turn = {
  sessionID: D073.sessionID,
  userMessageID: "u1",
  assistantMessageID: "a1",
  origin: "unknown",
  userText: "judge the case",
  assistantText: "",
  transcript: "USER: judge the case",
}

const context: AssembledContext = {
  text: `L0 TARGET ${AUTONOMOUS_ORIGIN_LABEL}\nUSER: judge the case`,
  estimatedTokens: 10,
  truncated: false,
}

const escalate = (rationale: string): TickDecision => ({
  action: "ESCALATE",
  rationale,
  citations: [{ session: D073.sessionID, messageID: "m1", quote: "q" }],
  confidence: 0.9,
  information_needs: [],
})

describe("autonomous-origin classification", () => {
  test("D073 bench path classified autonomous", () => {
    expect(classifyAutonomousOrigin({ directory: D073.directory, title: D073.title }, benchConfig)).toBe(true)
  })

  test("path glob alone classifies (title absent)", () => {
    expect(classifyAutonomousOrigin({ directory: D073.directory }, benchConfig)).toBe(true)
  })

  test("title prefix alone classifies", () => {
    expect(classifyAutonomousOrigin({ directory: "/home/ezotoff/AI_projects/veran", title: "bench-judge:qa" }, benchConfig)).toBe(true)
  })

  test("astra kickoff reuses the patterns.ts regex (no duplication)", () => {
    expect(matchesAstraKickoff("ASTRA Night 3")).toBe(true)
    expect(classifyAutonomousOrigin({ directory: "/home/ezotoff/AI_projects/kraken", kickoffText: "ASTRA Night 3" }, benchConfig)).toBe(true)
  })

  test("ordinary human session is not autonomous", () => {
    expect(classifyAutonomousOrigin({ directory: "/home/ezotoff/AI_projects/veran", title: "Fix the retry bug" }, benchConfig)).toBe(false)
  })

  test("globToRegExp anchors and spans path separators", () => {
    const re = globToRegExp("**/benchmarks/**/runs/**")
    expect(re.test(D073.directory)).toBe(true)
    expect(re.test("benchmarks/runs/x")).toBe(true)
    expect(re.test("/home/u/other/benchmarks/x")).toBe(false)
  })

  test("autonomousSessionIDs selects D073 and skips the human session", () => {
    const sessions: readonly Session[] = [
      { id: D073.sessionID, directory: D073.directory, title: D073.title },
      { id: "ses_human", directory: "/home/ezotoff/AI_projects/veran", title: "Fix bug" },
    ]
    const ids = autonomousSessionIDs(sessions, benchConfig)
    expect(ids.has(D073.sessionID)).toBe(true)
    expect(ids.has("ses_human")).toBe(false)
  })
})

describe("assembler autonomous-origin labels", () => {
  const base: AssembleInput = {
    target,
    targetHistory: [],
    targetHistoryCapPairs: 50,
    siblingTurnWindow: 3,
    tokenBudget: 40_000,
  }

  test("target card carries [origin: autonomous]", () => {
    const result = assembleContext({ ...base, targetAutonomous: true })
    expect(result.text).toContain(`L0 TARGET ${AUTONOMOUS_ORIGIN_LABEL}`)
  })

  test("target card omits the label when not autonomous", () => {
    const result = assembleContext(base)
    expect(result.text).not.toContain(AUTONOMOUS_ORIGIN_LABEL)
  })

  test("sibling card carries [origin: autonomous]", () => {
    const sibling: SiblingView = {
      sessionID: "ses-bench",
      title: "bench-judge:qa",
      lastActivityMs: Date.now(),
      turns: [],
      autonomous: true,
    }
    const result = assembleContext({ ...base, siblings: [sibling] })
    expect(result.text).toContain(`[HOT] ${AUTONOMOUS_ORIGIN_LABEL} bench-judge:qa`)
  })
})

describe("per-root autonomous-origin config", () => {
  const baseConfig = (roots: unknown[]): string =>
    JSON.stringify({
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

  test("per-root globs and prefixes parse and map to the classifier config", () => {
    const result = supervisorConfigSchema.safeParse(
      JSON.parse(baseConfig([{ path: "/tmp/opencode/bench", mode: "observe", autonomous_path_globs: ["**/benchmarks/**/runs/**"], autonomous_title_prefixes: ["bench-judge:"] }])),
    )
    if (!result.success) throw new Error("fixture config should parse")
    const root = result.data.roots[0]
    if (root === undefined) throw new Error("fixture root missing")
    expect(rootAutonomousOrigin(root)).toEqual({ pathGlobs: ["**/benchmarks/**/runs/**"], titlePrefixes: ["bench-judge:"] })
  })

  test("absent fields default to empty (no autonomous classification)", () => {
    const result = supervisorConfigSchema.safeParse(JSON.parse(baseConfig([{ path: "/tmp/opencode/proj", mode: "observe" }])))
    if (!result.success) throw new Error("fixture config should parse")
    const root = result.data.roots[0]
    if (root === undefined) throw new Error("fixture root missing")
    expect(rootAutonomousOrigin(root)).toEqual({ pathGlobs: [], titlePrefixes: [] })
  })
})

describe("autonomous-origin policy hook", () => {
  test("POLICY carries the drive-to-completion appendix", () => {
    expect(POLICY).toContain("AUTONOMOUS-ORIGIN SESSIONS")
    expect(POLICY).toContain("Drive it to completion")
    expect(POLICY).toContain("ESCALATE ONLY for a hard blocker")
    expect(POLICY).toContain("Never re-litigate the automation's own purpose")
  })

  test("stall in an autonomous session → CONTINUE, not ESCALATE", () => {
    const result = applyAutonomousOriginPolicy(escalate("the session stalled and produced no reply"), true)
    expect(result.decision.action).toBe("CONTINUE")
    expect(result.suppressed).toBeDefined()
  })

  test("suppression path yields a TICK_SKIPPED reason", () => {
    const result = applyAutonomousOriginPolicy(escalate("ordinary scope decision"), true)
    expect(result.suppressed).toContain("ESCALATE suppressed")
    expect(result.suppressed).toContain("drive-to-completion")
  })

  test("credential hard blocker still escalates", () => {
    const result = applyAutonomousOriginPolicy(escalate("missing credential: OPENAI_API_KEY is absent"), true)
    expect(result.decision.action).toBe("ESCALATE")
    expect(result.suppressed).toBeUndefined()
    expect(isCredentialBlocker("missing credential: OPENAI_API_KEY is absent")).toBe(true)
  })

  test("non-autonomous session is unchanged", () => {
    const result = applyAutonomousOriginPolicy(escalate("ordinary scope decision"), false)
    expect(result.decision.action).toBe("ESCALATE")
    expect(result.suppressed).toBeUndefined()
  })

  test("D073 fixture through the fork: ESCALATE on stall → CONTINUE", async () => {
    const adapter: ReasoningAdapter = {
      complete: async () =>
        JSON.stringify({
          action: "ESCALATE",
          rationale: "the judge session stalled and needs an operator decision",
          citations: [{ session: D073.sessionID, messageID: "m1", quote: "q" }],
          confidence: 0.9,
          information_needs: [],
        }),
    }
    const request: CollectForkRequest = {
      adapter,
      context,
      target,
      confidenceFloor: 0.6,
      root: D073.directory,
      executor: { run: async () => ({ text: "", tokens: 0, lookups: 0, empty: true }) },
      budget: { allow: () => true, record: () => {} },
      isIdle: async () => true,
      healthAmbiguous: false,
      hasSiblings: false,
      nowMs: () => 0,
      autonomous: true,
    }
    const decision = await runTickWithCollect(request)
    expect(decision.action).toBe("CONTINUE")
  })
})
