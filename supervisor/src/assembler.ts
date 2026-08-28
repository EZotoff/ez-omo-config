import type { Turn } from "./types"

export type AssembleInput = {
  readonly target: Turn
  readonly targetHistory: readonly Turn[]
  readonly siblingChanges: Readonly<Record<string, readonly Turn[]>>
  readonly targetHistoryCapPairs: number
  readonly siblingTurnWindow: number
  readonly tokenBudget: number
}

export type AssembledContext = { readonly text: string; readonly estimatedTokens: number; readonly truncated: boolean }

export function assembleContext(input: AssembleInput): AssembledContext {
  const targetHistory = input.targetHistory.filter((turn) => turn.transcript !== "").slice(-input.targetHistoryCapPairs)
  const siblings = Object.entries(input.siblingChanges).flatMap(([session, turns]) =>
    turns.filter((turn) => turn.transcript !== "").slice(-input.siblingTurnWindow).map((turn) => `SIBLING ${session}\n${turn.transcript}`),
  )
  const full = [`L0 TARGET\n${input.target.transcript}`, "L1 TARGET HISTORY", ...targetHistory.map((turn) => turn.transcript), ...siblings].join("\n\n")
  const maxChars = input.tokenBudget * 4
  const truncated = full.length > maxChars
  const text = truncated ? `${full.slice(0, Math.max(0, maxChars - 35))}\n[TRUNCATED: ABSTAIN REQUIRED]` : full
  return { text, estimatedTokens: Math.ceil(text.length / 4), truncated }
}
