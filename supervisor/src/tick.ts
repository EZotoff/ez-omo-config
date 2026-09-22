// allow: SIZE_OK — POLICY is a prompt (data, ~60 lines); the fork logic is ~200 LOC.
import { z } from "zod"
import type { Decision, Turn } from "./types"
import type { ReasoningAdapter } from "./adapter"
import type { AssembledContext } from "./assembler"
import {
  DEFAULT_COLLECT_BOUNDS,
  collectEligible,
  detectProxies,
  type CollectBudgetGate,
  type CollectEvent,
  type CollectRunner,
} from "./collect"

const citationSchema = z.object({ session: z.string().min(1), messageID: z.string().min(1), quote: z.string().min(1) }).strict()

/**
 * Structured information need — the collect-vs-decide fork signal. The model
 * names the exact missing evidence and how it would change the call; presence
 * of a need (not the confidence scalar) opens the bounded gather round.
 */
const informationNeedSchema = z.object({
  question: z.string().min(1),
  scope: z.enum(["sessions", "ledger", "cards"]),
  target: z.string().min(1),
  why: z.string().min(1),
  expected_effect: z.string().min(1),
}).strict()
export type InformationNeed = z.infer<typeof informationNeedSchema>

const evidenceEffectSchema = z.enum(["confirmed", "disconfirmed", "inconclusive"])
export type EvidenceEffect = z.infer<typeof evidenceEffectSchema>

const continueModeSchema = z.enum(["kick_start", "approve"])
export type ContinueMode = z.infer<typeof continueModeSchema>

const decisionSchema = z.object({
  action: z.enum(["ACCEPT", "ABSTAIN", "CONTINUE", "STEER", "REFORMULATE", "ESCALATE"]),
  target: z.string().min(1).optional(),
  rationale: z.string().min(1),
  citations: z.array(citationSchema),
  confidence: z.number().min(0).max(1),
  information_need: informationNeedSchema.nullable().optional(),
  information_needs: z.array(informationNeedSchema).max(3).optional(),
  evidence_effect: evidenceEffectSchema.optional(),
  mode: continueModeSchema.nullable().optional(),
}).strict()

/** Decision plus the fork fields the tick loop carries (types.ts Decision stays the shared shape). */
export type TickDecision = Decision & {
  readonly information_needs: readonly InformationNeed[]
  readonly evidence_effect?: EvidenceEffect
  readonly mode?: ContinueMode | null
}

function abstain(reason: string): TickDecision {
  return { action: "ABSTAIN", rationale: reason, citations: [], confidence: 0, information_needs: [] }
}

function extractJSON(raw: string): string {
  const fenced = raw.match(/```(?:json)?\s*([\s\S]*?)```/i)
  const candidate = fenced?.[1] ?? raw
  const start = candidate.indexOf("{")
  const end = candidate.lastIndexOf("}")
  return start >= 0 && end > start ? candidate.slice(start, end + 1) : candidate.trim()
}

const SCOPE_ALIASES: Readonly<Record<string, InformationNeed["scope"]>> = {
  SESSIONS: "sessions", SESSION: "sessions", SESSION_HISTORY: "sessions", HISTORY: "sessions",
  LEDGER: "ledger", LEDGER_LOOKUP: "ledger", TICKETS: "ledger", TICKET: "ledger",
  CARDS: "cards", CARD: "cards", SESSION_CARDS: "cards",
}

function normalizeNeed(value: unknown): unknown {
  if (typeof value !== "object" || value === null || Array.isArray(value)) return value
  const input = value as Record<string, unknown>
  const normalized: Record<string, unknown> = { ...input }
  const scopeRaw = normalized["scope"]
  if (typeof scopeRaw === "string") {
    const mapped = SCOPE_ALIASES[scopeRaw.toUpperCase().replace(/[ -]/g, "_")]
    if (mapped !== undefined) normalized["scope"] = mapped
  }
  if (normalized["expected_effect"] === undefined && typeof normalized["expectedEffect"] === "string") {
    normalized["expected_effect"] = normalized["expectedEffect"]
  }
  delete normalized["expectedEffect"]
  return normalized
}

function normalizeDecisionValue(value: unknown): unknown {
  if (typeof value !== "object" || value === null || Array.isArray(value)) return value
  const input = value as Record<string, unknown>
  const actionRaw = input["action"]
  if (typeof actionRaw !== "string") return value
  const actionUpper = actionRaw.toUpperCase().replace(/[ -]/g, "_")
  // Complete alias set observed in production GLM outputs (ledger + benchmark raws,
  // 2026-08-28): none, approve, allow, no_action, answer — all semantic no-ops here.
  const NOOP_ALIASES = new Set(["NONE", "NOOP", "NO_OP", "DO_NOTHING", "NO_ACTION", "APPROVE", "APPROVED", "ACCEPTED", "OK", "ALLOW", "ANSWER", "AGREE"])
  const EXPLAIN_ALIASES = new Set(["EXPLAIN", "REQUEST_EXPLANATION", "EXPLANATION", "DEMAND_EXPLANATION"])
  const action = NOOP_ALIASES.has(actionUpper)
    ? "ACCEPT"
    : EXPLAIN_ALIASES.has(actionUpper)
      ? "REFORMULATE"
      : actionUpper
  const normalized: Record<string, unknown> = { ...input, action }
  if (normalized["target"] === null) delete normalized["target"]
  const modeRaw = normalized["mode"]
  if (typeof modeRaw === "string") {
    const mode = modeRaw.trim().toUpperCase().replace(/[ -]/g, "_")
    if (["KICK_START", "KICKSTART", "CONTINUE", "RESUME"].includes(mode)) normalized["mode"] = "kick_start"
    else if (["APPROVE", "APPROVAL", "PROCEED", "GO_AHEAD"].includes(mode)) normalized["mode"] = "approve"
  }
  const citations = normalized["citations"]
  if ((action === "ACCEPT" || action === "ABSTAIN") && Array.isArray(citations) && citations.some((item) => typeof item !== "object" || item === null)) {
    normalized["citations"] = []
  }
  // Deterministic uncertainty proxy (spec-sanctioned): if a high-stakes action
  // cites evidence its own quote flags as unverified, and the model named no
  // need, synthesize one so the fork opens. Model cooperation is unreliable
  // (diagnosed 2026-09-20: 0/59 live decisions with needs).
  const UNCERTAIN = /\b(unclear|unverif\w*|not (?:yet )?agree\w*|no acceptance|unconfirm\w*|alleged|disput\w*|open question|not established)\b/i
  if (
    (normalized["action"] === "STEER" || normalized["action"] === "ESCALATE") &&
    !(Array.isArray(normalized["information_needs"]) && normalized["information_needs"].length > 0) &&
    Array.isArray(normalized["citations"])
  ) {
    const flagged = (normalized["citations"] as Array<Record<string, unknown>>).find(
      (c) => typeof c["quote"] === "string" && UNCERTAIN.test(c["quote"]),
    )
    if (flagged !== undefined && typeof flagged["quote"] === "string" && typeof flagged["session"] === "string") {
      const action = normalized["action"]
      normalized["information_needs"] = [{
        question: `Verify before acting: "${flagged["quote"].slice(0, 120)}"`,
        scope: "sessions",
        target: flagged["session"],
        why: "the cited evidence itself flags the fact as unverified",
        expected_effect: `confirm or flip the ${action}`,
      }]
    }
  }

  // Fork fields: accept singular `information_need` or plural `information_needs`,
  // canonicalize to the array (max 3). A malformed plural is left for the schema to reject.
  const plural = normalized["information_needs"]
  const single = normalized["information_need"]
  if (plural === undefined || Array.isArray(plural)) {
    const needs: unknown[] = Array.isArray(plural) ? [...plural] : []
    if (single !== undefined && single !== null) needs.push(single)
    if (needs.length > 0) normalized["information_needs"] = needs.slice(0, 3).map(normalizeNeed)
    else delete normalized["information_needs"]
    delete normalized["information_need"]
  }
  // evidence_effect is advisory (the confirmation-bias guard): tolerate free-form
  // model values instead of letting an off-enum word reject the whole decision.
  const evidenceRaw = normalized["evidence_effect"] ?? normalized["evidenceEffect"]
  if (typeof evidenceRaw === "string") {
    const lower = evidenceRaw.trim().toLowerCase()
    if (lower.startsWith("disconfirm")) normalized["evidence_effect"] = "disconfirmed"
    else if (lower.startsWith("confirm")) normalized["evidence_effect"] = "confirmed"
    else if (/inconclusive|unclear|neutral|no change|unchanged|insufficient/.test(lower)) normalized["evidence_effect"] = "inconclusive"
    else delete normalized["evidence_effect"]
  } else if (evidenceRaw !== undefined) {
    delete normalized["evidence_effect"]
  }
  delete normalized["evidenceEffect"]
  return normalized
}

export function parseDecision(raw: string, confidenceFloor: number, options?: { readonly provisional?: boolean }): TickDecision {
  let value: unknown
  try {
    value = normalizeDecisionValue(JSON.parse(extractJSON(raw)))
  } catch (error) {
    if (error instanceof SyntaxError) return abstain(`invalid JSON: ${raw.slice(0, 160)}`)
    throw error
  }
  const parsed = decisionSchema.safeParse(value)
  if (!parsed.success) return abstain(`decision schema validation failed: ${JSON.stringify(parsed.error.issues.slice(0, 3))} raw=${raw.slice(0, 160)}`)
  const decision: TickDecision = {
    action: parsed.data.action,
    ...(parsed.data.target === undefined ? {} : { target: parsed.data.target }),
    rationale: parsed.data.rationale,
    citations: parsed.data.citations,
    confidence: parsed.data.confidence,
    information_needs: parsed.data.information_needs ?? [],
    ...(parsed.data.evidence_effect === undefined ? {} : { evidence_effect: parsed.data.evidence_effect }),
    ...(parsed.data.mode === undefined ? {} : { mode: parsed.data.mode }),
  }
  // Tick 1 parses provisionally: the confidence floor and citation requirement
  // apply to the FINAL decision only, so a low-confidence lean that names a need
  // can still open the gather round.
  if (options?.provisional === true) return decision
  return applyFinalGates(decision, confidenceFloor)
}

/** Apply the confidence floor and the non-ACCEPT citation requirement to a final decision. */
export function applyFinalGates(decision: TickDecision, confidenceFloor: number): TickDecision {
  if (decision.confidence < confidenceFloor) return abstain("confidence below configured floor")
  if (decision.action !== "ACCEPT" && decision.action !== "ABSTAIN" && decision.citations.length === 0) {
    return abstain("non-accept decision requires citations")
  }
  return decision
}

/**
 * Autonomous-origin policy hook (ISS-08 / ISS-18). A machine-initiated session
 * has no human owner, so an ordinary ESCALATE would create a ticket nobody
 * answers. Drive it to completion instead: a non-credential ESCALATE is
 * suppressed and converted to CONTINUE; the caller logs the returned reason as
 * TICK_SKIPPED. A hard blocker (missing credential/secret) still escalates.
 */
const CREDENTIAL_TERM = /\b(?:credential|secret|api[ _-]?key|password|auth(?:entication)?|token)\b/i
const BLOCKER_TERM = /\b(?:missing|absent|expired|invalid|unavailable|required|needs?|cannot|can't|unable|no)\b/i

export function isCredentialBlocker(rationale: string): boolean {
  return CREDENTIAL_TERM.test(rationale) && BLOCKER_TERM.test(rationale)
}

export type AutonomousPolicyResult = {
  readonly decision: TickDecision
  /** Present when an ESCALATE was suppressed; the caller logs this as TICK_SKIPPED. */
  readonly suppressed?: string
}

export function applyAutonomousOriginPolicy(decision: TickDecision, autonomous: boolean): AutonomousPolicyResult {
  if (!autonomous || decision.action !== "ESCALATE") return { decision }
  if (isCredentialBlocker(decision.rationale)) return { decision }
  return {
    decision: {
      ...decision,
      action: "CONTINUE",
      rationale: `autonomous-origin: ESCALATE suppressed (no human owner) — drive-to-completion. ${decision.rationale}`
    },
    suppressed: "autonomous-origin: ESCALATE suppressed (non-credential) — drive-to-completion",
  }
}

export type TickRequest = {
  readonly adapter: ReasoningAdapter
  readonly context: AssembledContext
  readonly target: Turn
  readonly confidenceFloor: number
  /** True when the target session is autonomous-origin (drive-to-completion policy). */
  readonly autonomous?: boolean
  /** Called with the TICK_SKIPPED reason when an autonomous ESCALATE is suppressed. */
  readonly onSuppressed?: (reason: string) => void
}

export const POLICY = `You are the Project Supervisor for this workspace — a read-only stand-in for the human operator. You see exactly what the operator would see: top-level user messages and assistant replies. Tool output and subagent internals are hidden from you.

A worker session just completed the turn labeled TARGET below. Decide what the operator's stand-in should do.

Actions:
- ACCEPT: The exchange is COMPLETE — the requested outcome is DELIVERED in this reply, nothing further expected. A reply ending mid-sentence or mid-run, reporting jobs in flight, or only planning future work is NOT complete: CONTINUE, never ACCEPT.
- CONTINUE: The exchange is INCOMPLETE and needs a trivial go-ahead. A CONTINUE must declare mode: APPROVE for "shall I?"; KICK-START when stalled or errored with nothing in flight. A trivial in-scope request is APPROVE-CONTINUE, not ESCALATE. Operator "continue" means kick-start; "proceed" means approve. If there is a real decision — a choice between options, or authorization for consequential, out-of-scope, or destructive work — ESCALATE. If complete and nothing was asked, ACCEPT — never nudge a finished exchange.
- STEER: The worker is proceeding on stale or contradicted information established elsewhere in the supplied context. Cite the conflicting turns.
- REFORMULATE: The reply cannot be evaluated or acted on by a competent operator seeing only the supplied transcript. Two shapes: (a) a final answer that is all jargon, with no stated impact and no required decision; (b) conclusions resting on context NOT supplied — earlier agreements, session-internal shorthand, jargon chains, hidden tool state. In shape (b) demand a standalone account rebuilt from first principles: define the terms, state what changed and why it matters — relying on nothing from the session's interior.
- ESCALATE: A genuine operator decision is required: scope change, destructive or irreversible action, external dependency, or genuinely ambiguous intent. Describe the decision precisely.
- ABSTAIN: Insufficient evidence or confidence.

Decision rules:
1. CONTINUE means NO operator decision exists. If a real decision is pending, ESCALATE. If the work is simply finished, ACCEPT.
2. Use only facts from the supplied transcript. Every non-ACCEPT/ABSTAIN action must cite specific messages.
3. Sufficiency test before deciding: could a competent operator, seeing ONLY the supplied transcript, evaluate it? A pending decision → ESCALATE; missing foundations or context → REFORMULATE, rebuilt from first principles and relying on nothing from the session's interior; low confidence → ABSTAIN. A specific retrievable fact gap → information_need (rule 12), never guess.
4. Prefer the least intrusive correct action: ACCEPT before CONTINUE before STEER/REFORMULATE before ESCALATE.
5. Calibrate confidence: 0.9+ only with clear textual evidence.
6. Read operator messages for INTENT, not literal text. Intent outweighs its literal wording. Check the message and session purpose; on a probable typo or contradiction, ACCEPT if resolved or ESCALATE if a decision pends. Never CONTINUE on a reading that rests on a probable typo or self-contradiction.
7. CONTINUE is legal ONLY when the session is quiescent — nothing is in flight (no tool, command, or subagent running; the session is not busy). A running session needs no nudge. When in doubt, ABSTAIN.
8. A question is an INFORMATION request only if the operator needs the answer to make a decision. A question that provokes the worker's own reasoning ("why would X be the case?", "what is the purpose of Y?") is a thinking-prompt, not an info request — do not ESCALATE for it.
9. Deployment, promote, prod-write, and credential decisions are ESCALATE by default. Exception: if the project's trust config marks deploys autonomous, treat them as ordinary work.
10. L1 TARGET HISTORY contains this session's prior turns — it is your memory. Use it to resolve ambiguous references, detect contradictions, and honor decisions already made earlier in the session. If the operator already answered or gave a go-ahead earlier, the matter is SETTLED: do not re-ask it; STEER requires citing the specific conflicting message.
11. Your recent decisions and open tickets for this session are provided. Do not repeat a decision on the same unresolved cause. If you CONTINUEd last turn and the worker still has not delivered, STEER with the specific correction.
12. BEFORE choosing an action, run rule 3's FACT-gap check. If a specific retrievable fact is missing, emit 1-3 information_needs FIRST and return your action as provisional — the system will retrieve and re-ask. Each need names: question, scope (sessions|ledger|cards), target (sessionID or "root"), why, expected_effect (what answer flips the action). Emit information_needs: [] ONLY when the supplied transcript genuinely suffices. Never use needs to avoid deciding — a need must name retrievable evidence, not an operator's preference. At most 3.

AUTONOMOUS-ORIGIN SESSIONS: A target marked [origin: autonomous] was machine-initiated (bench-runner, ASTRA, heartbeat) and has no human owner. Drive it to completion: prefer CONTINUE on stall or error; do NOT ESCALATE for ordinary decisions. ESCALATE ONLY for a hard blocker (missing credential or secret), and mark it low-priority. Never re-litigate the automation's own purpose.

Return STRICT JSON only: {"action": "ACCEPT|ABSTAIN|CONTINUE|STEER|REFORMULATE|ESCALATE", "mode": "kick_start|approve|null", "target": null, "rationale": "...", "citations": [{"session": "...", "messageID": "...", "quote": "..."}], "confidence": 0.0-1.0, "information_needs": []}`

export const CONFIRMATION_INSTRUCTION = `CONFIRMATION CHECK: The GATHERED EVIDENCE above was retrieved because you named an information need. State in "evidence_effect" whether it CONFIRMED, DISCONFIRMED, or was INCONCLUSIVE for your provisional lean, and cite the gathered evidence in your citations.`

function adapterFailure(error: unknown): string {
  const status = typeof error === "object" && error !== null && "status" in error && typeof error.status === "number"
    ? ` HTTP ${error.status}`
    : ""
  return `reasoning adapter failed${status}`
}

export async function runTick(request: TickRequest): Promise<TickDecision> {
  if (request.context.truncated) return abstain("context exceeded token budget")
  const prompt = [
    POLICY,
    `TARGET SESSION ${request.target.sessionID} MESSAGE ${request.target.userMessageID}`,
    request.context.text,
  ].join("\n\n")
  try {
    const decision = parseDecision(await request.adapter.complete(prompt), request.confidenceFloor)
    const result = applyAutonomousOriginPolicy(decision, request.autonomous === true)
    if (result.suppressed !== undefined) request.onSuppressed?.(result.suppressed)
    return result.decision
  } catch (error) {
    return abstain(adapterFailure(error))
  }
}

export type CollectForkRequest = {
  readonly adapter: ReasoningAdapter
  readonly context: AssembledContext
  readonly target: Turn
  readonly confidenceFloor: number
  readonly root: string
  readonly executor: CollectRunner
  readonly budget: CollectBudgetGate
  readonly isIdle: () => Promise<boolean>
  readonly healthAmbiguous: boolean
  readonly hasSiblings: boolean
  readonly nowMs: () => number
  readonly onCollect?: (event: CollectEvent) => void
  /** True when the target session is autonomous-origin (drive-to-completion policy). */
  readonly autonomous?: boolean
  /** Called with the TICK_SKIPPED reason when an autonomous ESCALATE is suppressed. */
  readonly onSuppressed?: (reason: string) => void
}

/**
 * The collect-vs-decide fork, run INSIDE one tick (the grace clock is never
 * re-armed; the FSM sees a single TICK → DECIDED). One gather round, ≤3 lookups,
 * ≤30s, ≤8k gathered tokens. If tick 2 still names a need it decides or ABSTAINs
 * — there is no second round.
 */
export async function runTickWithCollect(request: CollectForkRequest): Promise<TickDecision> {
  const decision = await runCollectFork(request)
  const result = applyAutonomousOriginPolicy(decision, request.autonomous === true)
  if (result.suppressed !== undefined) request.onSuppressed?.(result.suppressed)
  return result.decision
}

async function runCollectFork(request: CollectForkRequest): Promise<TickDecision> {
  if (request.context.truncated) return abstain("context exceeded token budget")
  const header = `TARGET SESSION ${request.target.sessionID} MESSAGE ${request.target.userMessageID}`
  let raw1: string
  try {
    raw1 = await request.adapter.complete([POLICY, header, request.context.text].join("\n\n"))
  } catch (error) {
    return abstain(adapterFailure(error))
  }
  const d1 = parseDecision(raw1, request.confidenceFloor, { provisional: true })
  if (d1.action === "ABSTAIN") return d1
  const needs = d1.information_needs
  if (needs.length === 0) return applyFinalGates(d1, request.confidenceFloor)

  const now = request.nowMs()
  const budgetAvailable = request.budget.allow(request.root, request.target.sessionID, now)
  const proxies = detectProxies({ decision: d1, target: request.target, context: request.context, hasSiblings: request.hasSiblings })
  const eligible = collectEligible({ action: d1.action, needs, healthAmbiguous: request.healthAmbiguous, proxyFired: proxies.fired, budgetAvailable })
  if (!eligible) {
    request.onCollect?.({ needs, outcome: budgetAvailable ? "ineligible" : "budget-blocked", tokens: 0, changed: false, evidenceEffect: "inconclusive" })
    return applyFinalGates(d1, request.confidenceFloor)
  }

  if (!(await request.isIdle())) {
    request.onCollect?.({ needs, outcome: "discarded", tokens: 0, changed: false, evidenceEffect: "inconclusive" })
    return abstain("session resumed during collect")
  }

  const gathered = await request.executor.run(needs, DEFAULT_COLLECT_BOUNDS)
  // Re-check idle after gathering: if the session moved while we collected, the
  // moment has passed — discard rather than decide on stale evidence.
  if (!(await request.isIdle())) {
    request.onCollect?.({ needs, outcome: "discarded", tokens: gathered.tokens, changed: false, evidenceEffect: "inconclusive" })
    return abstain("session resumed during collect")
  }
  if (gathered.empty) {
    request.onCollect?.({ needs, outcome: "empty", tokens: 0, changed: false, evidenceEffect: "inconclusive" })
    return applyFinalGates(d1, request.confidenceFloor)
  }

  const prompt2 = [
    POLICY,
    header,
    request.context.text,
    "GATHERED EVIDENCE",
    gathered.text,
    `YOUR PROVISIONAL LEAN: ${d1.action}`,
    CONFIRMATION_INSTRUCTION,
  ].join("\n\n")
  let raw2: string
  try {
    raw2 = await request.adapter.complete(prompt2)
  } catch (error) {
    return abstain(adapterFailure(error))
  }
  const d2 = parseDecision(raw2, request.confidenceFloor)
  request.budget.record(request.root, request.target.sessionID, gathered.tokens, now)
  request.onCollect?.({
    needs,
    outcome: "gathered",
    tokens: gathered.tokens,
    changed: d2.action !== d1.action,
    evidenceEffect: d2.evidence_effect ?? "inconclusive",
  })
  return d2
}
