import type { AssembledContext } from "./assembler"
import { projectTurns } from "./projector"
import type { InformationNeed, TickDecision } from "./tick"
import type { Action, LedgerRecord, Message, Session, Turn } from "./types"

/**
 * Collect-vs-decide fork executor (design: supervisor/collect-vs-decide-design.md).
 *
 * Three primitives, all routed through the top-level U/A projection — the
 * epistemic boundary is enforced HERE, in code, not in the prompt:
 *   - session_history(sessionID)  → listMessages + projectTurns (U/A only)
 *   - ledger_lookup(sessionID|root) → the supervisor's own ledger + open tickets
 *   - session_cards(root)         → listSessions metadata (titles/recency)
 * No grep over tool output, no raw message parts, no tool state.
 */

export type CollectClient = {
  readonly listSessions: (directory: string) => Promise<readonly Session[]>
  readonly listAllSessions: () => Promise<readonly Session[]>
  readonly listMessages: (sessionID: string, directory: string) => Promise<readonly Message[]>
}

export type OpenTicketView = {
  readonly id: string
  readonly actionClass: Action
  readonly question: string
  readonly target: { readonly sessionID: string }
}

export type CollectDeps = {
  readonly client: CollectClient
  readonly root: string
  readonly ledgerRecords: () => readonly LedgerRecord[]
  readonly openItems: () => readonly OpenTicketView[]
  readonly nowMs: () => number
}

export type CollectBounds = {
  readonly deadlineMs: number
  readonly maxLookups: number
  readonly tokenCap: number
  readonly perLookupTokenCap: number
  readonly historyTurnWindow: number
}

export const DEFAULT_COLLECT_BOUNDS: CollectBounds = {
  deadlineMs: 30_000,
  maxLookups: 3,
  tokenCap: 8_000,
  perLookupTokenCap: 2_500,
  historyTurnWindow: 20,
}

export type GatheredEvidence = {
  readonly text: string
  readonly tokens: number
  readonly lookups: number
  readonly empty: boolean
}

export type CollectOutcome = "gathered" | "empty" | "discarded" | "budget-blocked" | "ineligible"

export type CollectEvent = {
  readonly needs: readonly InformationNeed[]
  readonly outcome: CollectOutcome
  readonly tokens: number
  readonly changed: boolean
  readonly evidenceEffect: "confirmed" | "disconfirmed" | "inconclusive"
}

/** The loop depends on this narrow seam so tests can stub gathering without HTTP. */
export interface CollectRunner {
  run(needs: readonly InformationNeed[], bounds: CollectBounds): Promise<GatheredEvidence>
}

export interface CollectBudgetGate {
  allow(root: string, sessionID: string, nowMs: number): boolean
  record(root: string, sessionID: string, tokens: number, nowMs: number): void
}

const estimateTokens = (text: string): number => Math.ceil(text.length / 4)

const ageLabel = (ageMs: number): string => {
  const minutes = Math.floor(Math.max(0, ageMs) / 60_000)
  if (minutes < 60) return `${minutes}m ago`
  const hours = Math.floor(minutes / 60)
  if (hours < 24) return `${hours}h ago`
  return `${Math.floor(hours / 24)}d ago`
}

type LookupResult = { readonly text: string }

export class CollectExecutor implements CollectRunner {
  constructor(private readonly deps: CollectDeps) {}

  async run(needs: readonly InformationNeed[], bounds: CollectBounds): Promise<GatheredEvidence> {
    const startedAt = this.deps.nowMs()
    const blocks: string[] = []
    let tokens = 0
    let lookups = 0
    for (const need of needs.slice(0, bounds.maxLookups)) {
      if (this.deps.nowMs() - startedAt > bounds.deadlineMs) break
      if (tokens >= bounds.tokenCap) break
      const result = await this.lookup(need, bounds)
      lookups += 1
      if (result === undefined || result.text.trim() === "") continue
      const remaining = bounds.tokenCap - tokens
      const cost = estimateTokens(result.text)
      if (cost > remaining) {
        const truncated = result.text.slice(0, Math.max(0, remaining) * 4)
        if (truncated.trim() === "") break
        blocks.push(`[${need.scope}] ${need.question}\n${truncated}\n[TRUNCATED]`)
        tokens += estimateTokens(truncated)
        break
      }
      blocks.push(`[${need.scope}] ${need.question}\n${result.text}`)
      tokens += cost
    }
    const text = blocks.join("\n\n")
    return { text, tokens, lookups, empty: text.trim() === "" }
  }

  private async lookup(need: InformationNeed, bounds: CollectBounds): Promise<LookupResult | undefined> {
    switch (need.scope) {
      case "sessions":
        return this.sessionHistory(need.target, bounds)
      case "ledger":
        return this.ledgerLookup(need.target)
      case "cards":
        return this.sessionCards()
    }
  }

  private async resolveDirectory(sessionID: string): Promise<string | undefined> {
    const local = await this.deps.client.listSessions(this.deps.root)
    const found = local.find((session) => session.id === sessionID)
    if (found !== undefined) return found.directory
    const all = await this.deps.client.listAllSessions()
    return all.find((session) => session.id === sessionID)?.directory
  }

  private async sessionHistory(sessionID: string, bounds: CollectBounds): Promise<LookupResult | undefined> {
    const directory = await this.resolveDirectory(sessionID)
    if (directory === undefined) return undefined
    const messages = await this.deps.client.listMessages(sessionID, directory)
    const turns = projectTurns(messages, { humanMessageIDs: new Set(), supervisorMessageIDs: new Set() })
    const selected = turns.filter((turn) => turn.transcript !== "").slice(-bounds.historyTurnWindow)
    if (selected.length === 0) return undefined
    const text = selected
      .map((turn) => `SESSION ${sessionID}\nUSER (${turn.userMessageID}): ${turn.userText}${turn.assistantText === "" ? "" : `\nASSISTANT (${turn.assistantMessageID ?? "?"}): ${turn.assistantText}`}`)
      .join("\n\n")
    return { text }
  }

  private ledgerLookup(target: string): LookupResult | undefined {
    const lines: string[] = []
    const decisions = this.deps.ledgerRecords().filter((record) => record.type === "TICK_DECIDED").slice(-10)
    for (const record of decisions) {
      const payload = record.payload
      if (typeof payload !== "object" || payload === null) continue
      const sessionID = (payload as Record<string, unknown>)["sessionID"]
      if (target !== "root" && target !== "recent" && sessionID !== target) continue
      const decision = (payload as Record<string, unknown>)["decision"]
      const action = typeof decision === "object" && decision !== null ? (decision as Record<string, unknown>)["action"] : undefined
      const rationale = typeof decision === "object" && decision !== null ? (decision as Record<string, unknown>)["rationale"] : undefined
      lines.push(`- seq ${record.seq} ${record.timestamp} ${String(action)}: ${String(rationale).slice(0, 160)}`)
    }
    const open = this.deps.openItems().filter((item) => target === "root" || target === "recent" || item.target.sessionID === target)
    for (const item of open.slice(0, 5)) {
      lines.push(`- OPEN TICKET ${item.id} (${item.actionClass}): ${item.question.slice(0, 160)}`)
    }
    return lines.length === 0 ? undefined : { text: lines.join("\n") }
  }

  private async sessionCards(): Promise<LookupResult | undefined> {
    const sessions = await this.deps.client.listSessions(this.deps.root)
    const now = this.deps.nowMs()
    const lines = sessions
      .filter((session) => session.parentID === undefined)
      .sort((left, right) => (right.timeUpdatedMs ?? 0) - (left.timeUpdatedMs ?? 0))
      .slice(0, 30)
      .map((session) => `- ${session.title ?? session.id} (${ageLabel(now - (session.timeUpdatedMs ?? now))}) — ${session.id}`)
    return lines.length === 0 ? undefined : { text: lines.join("\n") }
  }
}

export type CollectGateInput = {
  readonly action: Action
  readonly needs: readonly InformationNeed[]
  readonly healthAmbiguous: boolean
  readonly proxyFired: boolean
  readonly budgetAvailable: boolean
}

/**
 * Stake-scaled eligibility (design §4): STEER/ESCALATE collect by default;
 * CONTINUE needs ambiguous health or a proxy; ACCEPT/REFORMULATE need a proxy;
 * ABSTAIN never collects. Budget exhaustion disables the fork for every action.
 */
export function collectEligible(input: CollectGateInput): boolean {
  if (input.action === "ABSTAIN") return false
  if (input.needs.length === 0) return false
  if (!input.budgetAvailable) return false
  if (input.action === "STEER" || input.action === "ESCALATE") return true
  if (input.action === "CONTINUE") return input.healthAmbiguous || input.proxyFired
  return input.proxyFired
}

export type ProxySignals = { readonly fired: boolean; readonly reasons: readonly string[] }

const SESSION_ID_RE = /ses_[A-Za-z0-9]+/g
const REFERENCE_RE = /\b(as agreed|earlier|previously|last time|we discussed|ticket\s+\w+|q\d+)\b/i
const CONTRADICTION_RE = /\b(remove me|don't|dont|never|stop|wait|actually|instead)\b/i

/**
 * Deterministic forcing function (design §1): cheap string/structure checks that
 * synthesize a collect trigger when the model did not name one. No LLM.
 */
export function detectProxies(input: {
  readonly decision: TickDecision
  readonly target: Turn
  readonly context: AssembledContext
  readonly hasSiblings: boolean
}): ProxySignals {
  const reasons: string[] = []
  if (input.target.assistantText.trim() === "") reasons.push("P-empty")
  if ((input.decision.action === "STEER" || input.decision.action === "ESCALATE") && input.hasSiblings) {
    if (input.decision.citations.every((citation) => citation.session === input.target.sessionID)) reasons.push("P-cross")
  }
  const referenced = input.decision.rationale.match(SESSION_ID_RE) ?? []
  if (referenced.some((id) => !input.context.text.includes(id)) || REFERENCE_RE.test(input.decision.rationale)) reasons.push("P-ref")
  if (input.decision.action === "CONTINUE" && CONTRADICTION_RE.test(input.target.userText)) reasons.push("P-contra")
  return { fired: reasons.length > 0, reasons }
}

export type CollectBudgetLimits = {
  readonly dailyRoundsPerRoot: number
  readonly dailyTokensPerRoot: number
  readonly dailyRoundsPerSession: number
}

export const DEFAULT_COLLECT_BUDGET_LIMITS: CollectBudgetLimits = {
  dailyRoundsPerRoot: 15,
  dailyTokensPerRoot: 200_000,
  dailyRoundsPerSession: 2,
}

/** Per-root and per-session daily counters (design §5 runaway guards). */
export class CollectBudget implements CollectBudgetGate {
  private readonly rootRounds = new Map<string, number>()
  private readonly rootTokens = new Map<string, number>()
  private readonly sessionRounds = new Map<string, number>()

  constructor(private readonly limits: CollectBudgetLimits = DEFAULT_COLLECT_BUDGET_LIMITS) {}

  private dayKey(nowMs: number): string {
    return new Date(nowMs).toISOString().slice(0, 10)
  }

  allow(root: string, sessionID: string, nowMs: number): boolean {
    const day = this.dayKey(nowMs)
    if ((this.rootRounds.get(`${root}|${day}`) ?? 0) >= this.limits.dailyRoundsPerRoot) return false
    if ((this.rootTokens.get(`${root}|${day}`) ?? 0) >= this.limits.dailyTokensPerRoot) return false
    if ((this.sessionRounds.get(`${sessionID}|${day}`) ?? 0) >= this.limits.dailyRoundsPerSession) return false
    return true
  }

  record(root: string, sessionID: string, tokens: number, nowMs: number): void {
    const day = this.dayKey(nowMs)
    this.rootRounds.set(`${root}|${day}`, (this.rootRounds.get(`${root}|${day}`) ?? 0) + 1)
    this.rootTokens.set(`${root}|${day}`, (this.rootTokens.get(`${root}|${day}`) ?? 0) + tokens)
    this.sessionRounds.set(`${sessionID}|${day}`, (this.sessionRounds.get(`${sessionID}|${day}`) ?? 0) + 1)
  }
}
