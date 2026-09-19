import type { Turn } from "./types"

export type AssembleInput = {
  readonly target: Turn
  readonly targetHistory: readonly Turn[]
  readonly siblingChanges: Readonly<Record<string, readonly Turn[]>>
  readonly targetHistoryCapPairs: number
  readonly siblingTurnWindow: number
  readonly tokenBudget: number
  /** L3 self-memory: supervisor's recent decisions on the target + open attention items on the root. */
  readonly selfMemory?: SelfMemory
}

export type SelfMemory = {
  readonly decisions: readonly { readonly action: string; readonly rationale: string; readonly decidedAtMs: number }[]
  readonly openItems: readonly { readonly id: string; readonly question: string; readonly createdAtMs: number }[]
  readonly nowMs: number
}

export type AssembledContext = { readonly text: string; readonly estimatedTokens: number; readonly truncated: boolean }

const ageLabel = (ageMs: number): string => {
  const minutes = Math.floor(ageMs / 60_000)
  if (minutes < 60) return `${minutes}m ago`
  const hours = Math.floor(minutes / 60)
  if (hours < 24) return `${hours}h ago`
  return `${Math.floor(hours / 24)}d ago`
}

const SELF_MEMORY_MAX_CHARS = 500 * 4

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

export function assembleContext(input: AssembleInput): AssembledContext {
  const targetHistory = input.targetHistory.filter((turn) => turn.transcript !== "").slice(-input.targetHistoryCapPairs)
  const siblings = Object.entries(input.siblingChanges).flatMap(([session, turns]) =>
    turns.filter((turn) => turn.transcript !== "").slice(-input.siblingTurnWindow).map((turn) => `SIBLING ${session}\n${turn.transcript}`),
  )
  const blocks = [
    `L0 TARGET\n${input.target.transcript}`,
    "L1 TARGET HISTORY",
    ...targetHistory.map((turn) => turn.transcript),
    ...siblings,
    ...(input.selfMemory === undefined ? [] : [renderSelfMemory(input.selfMemory)]),
  ]
  const full = blocks.join("\n\n")
  const maxChars = input.tokenBudget * 4
  const truncated = full.length > maxChars
  const text = truncated ? `${full.slice(0, Math.max(0, maxChars - 35))}\n[TRUNCATED: ABSTAIN REQUIRED]` : full
  return { text, estimatedTokens: Math.ceil(text.length / 4), truncated }
}
