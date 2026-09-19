import type { RootTrust } from "./config"
import { AUTONOMOUS_ORIGIN_LABEL } from "./origins"
import type { Turn } from "./types"

export type SiblingTier = "HOT" | "WARM" | "COOL" | "COLD"

/** One sibling session as seen by the assembler: title + last-activity age + projected turns. */
export type SiblingView = {
  readonly sessionID: string
  readonly title?: string
  readonly lastActivityMs?: number
  readonly turns: readonly Turn[]
  /** True when the sibling session is autonomous-origin (machine-initiated). */
  readonly autonomous?: boolean
}

/** Per-tier token sub-budgets (oracle-context-architecture allocation). */
export type TierBudgets = {
  readonly targetHistory: number
  readonly hot: number
  readonly warm: number
  readonly cool: number
  readonly cold: number
}

/** Blocks dropped or trimmed to fit the budget, in the order they were degraded. */
export type DegradationStep = "COLD" | "COOL" | "WARM" | "SIBLINGS" | "L1-OLDEST" | "HOT" | "SELF-MEMORY"

export type AssembleInput = {
  readonly target: Turn
  readonly targetHistory: readonly Turn[]
  /** v2 recency-tiered sibling views (preferred). */
  readonly siblings?: readonly SiblingView[]
  /** Legacy flat sibling map; used only when `siblings` is absent. */
  readonly siblingChanges?: Readonly<Record<string, readonly Turn[]>>
  readonly targetHistoryCapPairs: number
  readonly siblingTurnWindow: number
  readonly tokenBudget: number
  readonly tierBudgets?: TierBudgets
  readonly nowMs?: number
  /** L3 self-memory: supervisor's recent decisions on the target + open attention items on the root. */
  readonly selfMemory?: SelfMemory
  /** Target root's trust flags (policy rule 9 hook). Absent = untrusted (fail-closed). */
  readonly rootTrust?: RootTrust
  /** True when the TARGET session is autonomous-origin (drive-to-completion policy hook). */
  readonly targetAutonomous?: boolean
}

export type SelfMemory = {
  readonly decisions: readonly { readonly action: string; readonly rationale: string; readonly decidedAtMs: number }[]
  readonly openItems: readonly { readonly id: string; readonly question: string; readonly createdAtMs: number }[]
  readonly nowMs: number
}

export type AssembledContext = {
  readonly text: string
  readonly estimatedTokens: number
  /** True only when L0 alone overflows the budget (the sole ABSTAIN-by-truncation case). */
  readonly truncated: boolean
  /** v2: blocks dropped or trimmed to fit the budget, in degradation order (empty = none). */
  readonly degraded?: readonly DegradationStep[]
}

const HOUR_MS = 3_600_000
const DAY_MS = 86_400_000
const HOT_MAX_MS = 2 * HOUR_MS
const WARM_MAX_MS = 24 * HOUR_MS
const COOL_MAX_MS = 7 * DAY_MS
const HOT_PAIRS = 8
const WARM_PAIRS = 3
const SELF_MEMORY_MAX_CHARS = 500 * 4

/** Default tier sub-budgets: the oracle allocation (40k → 15k/8k/6k/4k/2k). */
export const defaultTierBudgets = (tokenBudget: number): TierBudgets => ({
  targetHistory: Math.floor(tokenBudget * 0.375),
  hot: Math.floor(tokenBudget * 0.2),
  warm: Math.floor(tokenBudget * 0.15),
  cool: Math.floor(tokenBudget * 0.1),
  cold: Math.floor(tokenBudget * 0.05),
})

const estimateTokens = (text: string): number => Math.ceil(text.length / 4)

const ageLabel = (ageMs: number): string => {
  const minutes = Math.floor(ageMs / 60_000)
  if (minutes < 60) return `${minutes}m ago`
  const hours = Math.floor(minutes / 60)
  if (hours < 24) return `${hours}h ago`
  return `${Math.floor(hours / 24)}d ago`
}

const tierFor = (lastActivityMs: number | undefined, nowMs: number): SiblingTier => {
  if (lastActivityMs === undefined) return "COLD"
  const age = nowMs - lastActivityMs
  if (age < HOT_MAX_MS) return "HOT"
  if (age < WARM_MAX_MS) return "WARM"
  if (age < COOL_MAX_MS) return "COOL"
  return "COLD"
}

const siblingTitle = (sibling: SiblingView): string =>
  sibling.title !== undefined && sibling.title.trim() !== "" ? sibling.title : sibling.sessionID

const renderSibling = (tier: SiblingTier, sibling: SiblingView, nowMs: number): string => {
  const age = sibling.lastActivityMs === undefined ? "age unknown" : ageLabel(nowMs - sibling.lastActivityMs)
  const header = `[${tier}]${sibling.autonomous === true ? ` ${AUTONOMOUS_ORIGIN_LABEL}` : ""} ${siblingTitle(sibling)} (${age}) — ${sibling.sessionID}`
  const turns = sibling.turns.filter((turn) => turn.transcript !== "")
  if (tier === "COLD") return header
  if (tier === "COOL") {
    const assistant = turns.at(-1)?.assistantText.trim() ?? ""
    return assistant === "" ? header : `${header}\nASSISTANT: ${assistant}`
  }
  const depth = tier === "HOT" ? HOT_PAIRS : WARM_PAIRS
  const selected = turns.slice(-depth)
  return selected.length === 0 ? header : `${header}\n${selected.map((turn) => turn.transcript).join("\n\n")}`
}

/**
 * Uniform depth per tier; overflow drops the oldest siblings (recency order only —
 * no semantic ranking among strands, per the operator memory model).
 */
const renderTier = (tier: SiblingTier, siblings: readonly SiblingView[], nowMs: number, subBudget: number): string | undefined => {
  if (siblings.length === 0) return undefined
  const ordered = [...siblings].sort((left, right) => (right.lastActivityMs ?? 0) - (left.lastActivityMs ?? 0))
  const rendered: string[] = []
  let used = 0
  for (const sibling of ordered) {
    const block = renderSibling(tier, sibling, nowMs)
    const cost = estimateTokens(block)
    if (rendered.length > 0 && used + cost > subBudget) break
    rendered.push(block)
    used += cost
  }
  return rendered.join("\n\n")
}

const renderHistory = (turns: readonly Turn[]): string =>
  turns.length === 0 ? "L1 TARGET HISTORY" : `L1 TARGET HISTORY\n${turns.map((turn) => turn.transcript).join("\n\n")}`

const trimHistoryToBudget = (turns: readonly Turn[], subBudget: number): readonly Turn[] => {
  let kept = [...turns]
  while (kept.length > 0 && estimateTokens(renderHistory(kept)) > subBudget) kept = kept.slice(1)
  return kept
}

const renderLegacySiblings = (changes: Readonly<Record<string, readonly Turn[]>>, window: number): string | undefined => {
  const blocks = Object.entries(changes).flatMap(([session, turns]) =>
    turns.filter((turn) => turn.transcript !== "").slice(-window).map((turn) => `SIBLING ${session}\n${turn.transcript}`))
  return blocks.length === 0 ? undefined : blocks.join("\n\n")
}

function renderSelfMemory(memory: SelfMemory): string {
  const lines = [
    "L3 SELF-MEMORY",
    "YOUR RECENT DECISIONS on this session:",
    ...memory.decisions.map((decision) => `- ${decision.action} (${ageLabel(memory.nowMs - decision.decidedAtMs)}) — ${decision.rationale.split("\n")[0]?.slice(0, 120) ?? ""}`),
  ]
  if (memory.openItems.length > 0) {
    lines.push("OPEN ATTENTION ITEMS on this project's root:")
    lines.push(...memory.openItems.map((item) => `- ${item.id} (${ageLabel(memory.nowMs - item.createdAtMs)}): ${item.question.split("\n")[0]?.slice(0, 120) ?? ""}`))
  }
  const full = lines.join("\n")
  if (full.length <= SELF_MEMORY_MAX_CHARS) return full
  const kept: string[] = []
  let budget = SELF_MEMORY_MAX_CHARS
  for (const line of lines) {
    if (budget < line.length + 1) break
    kept.push(line)
    budget -= line.length + 1
  }
  return `${kept.join("\n")}\n[SELF-MEMORY TRIMMED]`
}

const renderRootTrust = (trust: RootTrust | undefined): string =>
  `ROOT TRUST: autonomous_deploy=${trust?.autonomous_deploy ?? false}; autonomous_credentialed_actions=${trust?.autonomous_credentialed_actions ?? false}`

export function assembleContext(input: AssembleInput): AssembledContext {
  const nowMs = input.nowMs ?? Date.now()
  const budgets = input.tierBudgets ?? defaultTierBudgets(input.tokenBudget)

  const l0 = `L0 TARGET${input.targetAutonomous === true ? ` ${AUTONOMOUS_ORIGIN_LABEL}` : ""}\n${input.target.transcript}`
  const l0Tokens = estimateTokens(l0)
  if (l0Tokens > input.tokenBudget) {
    return { text: l0, estimatedTokens: l0Tokens, truncated: true, degraded: [] }
  }

  let historyTurns = trimHistoryToBudget(
    input.targetHistory.filter((turn) => turn.transcript !== "").slice(-input.targetHistoryCapPairs),
    budgets.targetHistory,
  )

  const tiered = input.siblings !== undefined
  const grouped: Record<SiblingTier, SiblingView[]> = { HOT: [], WARM: [], COOL: [], COLD: [] }
  if (tiered) {
    for (const sibling of input.siblings ?? []) grouped[tierFor(sibling.lastActivityMs, nowMs)].push(sibling)
  }
  let hot = tiered ? renderTier("HOT", grouped.HOT, nowMs, budgets.hot) : undefined
  let warm = tiered ? renderTier("WARM", grouped.WARM, nowMs, budgets.warm) : undefined
  let cool = tiered ? renderTier("COOL", grouped.COOL, nowMs, budgets.cool) : undefined
  let cold = tiered ? renderTier("COLD", grouped.COLD, nowMs, budgets.cold) : undefined
  let flat = tiered ? undefined : renderLegacySiblings(input.siblingChanges ?? {}, input.siblingTurnWindow)
  let selfMemory = input.selfMemory === undefined ? undefined : renderSelfMemory(input.selfMemory)

  const rootTrust = renderRootTrust(input.rootTrust)
  const degraded: DegradationStep[] = []
  const total = (): number => estimateTokens(
    [l0, renderHistory(historyTurns), hot, warm, cool, cold, flat, selfMemory, rootTrust]
      .filter((block): block is string => block !== undefined)
      .join("\n\n"),
  )

  // Degradation order: COLD → COOL → WARM → (legacy flat siblings) → L1 oldest-first.
  if (total() > input.tokenBudget && cold !== undefined) { cold = undefined; degraded.push("COLD") }
  if (total() > input.tokenBudget && cool !== undefined) { cool = undefined; degraded.push("COOL") }
  if (total() > input.tokenBudget && warm !== undefined) { warm = undefined; degraded.push("WARM") }
  if (total() > input.tokenBudget && flat !== undefined) { flat = undefined; degraded.push("SIBLINGS") }
  if (total() > input.tokenBudget) {
    const before = historyTurns.length
    while (historyTurns.length > 0 && total() > input.tokenBudget) historyTurns = historyTurns.slice(1)
    if (historyTurns.length < before) degraded.push("L1-OLDEST")
  }
  // Safety net beyond the documented order: HOT and L3 are never dropped while
  // cheaper content remains, but must yield before we would ABSTAIN.
  if (total() > input.tokenBudget && hot !== undefined) { hot = undefined; degraded.push("HOT") }
  if (total() > input.tokenBudget && selfMemory !== undefined) { selfMemory = undefined; degraded.push("SELF-MEMORY") }

  const blocks = [l0, renderHistory(historyTurns), hot, warm, cool, cold, flat, selfMemory, rootTrust]
    .filter((block): block is string => block !== undefined)
  const text = blocks.join("\n\n")
  const estimatedTokens = estimateTokens(text)
  if (estimatedTokens > input.tokenBudget) {
    // Only L0 remains and it fits (checked above): never ABSTAIN-by-truncation.
    return { text: l0, estimatedTokens: l0Tokens, truncated: false, degraded }
  }
  return { text, estimatedTokens, truncated: false, degraded }
}
