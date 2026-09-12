import { z } from "zod"
import type { Decision, Turn } from "./types"
import type { ReasoningAdapter } from "./adapter"
import type { AssembledContext } from "./assembler"

const citationSchema = z.object({ session: z.string().min(1), messageID: z.string().min(1), quote: z.string().min(1) }).strict()
const decisionSchema = z.object({
  action: z.enum(["ACCEPT", "ABSTAIN", "CONTINUE", "STEER", "REFORMULATE", "DEMAND_EXPLANATION", "ESCALATE"]),
  target: z.string().min(1).optional(),
  rationale: z.string().min(1),
  citations: z.array(citationSchema),
  confidence: z.number().min(0).max(1),
}).strict()

function abstain(reason: string): Decision {
  return { action: "ABSTAIN", rationale: reason, citations: [], confidence: 0 }
}

function extractJSON(raw: string): string {
  const fenced = raw.match(/```(?:json)?\\s*([\\s\\S]*?)```/i)
  const candidate = fenced?.[1] ?? raw
  const start = candidate.indexOf("{")
  const end = candidate.lastIndexOf("}")
  return start >= 0 && end > start ? candidate.slice(start, end + 1) : candidate.trim()
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
      ? "DEMAND_EXPLANATION"
      : actionUpper
  const normalized: Record<string, unknown> = { ...input, action }
  if (normalized["target"] === null) delete normalized["target"]
  const citations = normalized["citations"]
  if ((action === "ACCEPT" || action === "ABSTAIN") && Array.isArray(citations) && citations.some((item) => typeof item !== "object" || item === null)) {
    normalized["citations"] = []
  }
  return normalized
}

export function parseDecision(raw: string, confidenceFloor: number): Decision {
  let value: unknown
  try {
    value = normalizeDecisionValue(JSON.parse(extractJSON(raw)))
  } catch (error) {
    if (error instanceof SyntaxError) return abstain(`invalid JSON: ${raw.slice(0, 160)}`)
    throw error
  }
  const parsed = decisionSchema.safeParse(value)
  if (!parsed.success) return abstain(`decision schema validation failed: ${JSON.stringify(parsed.error.issues.slice(0, 3))} raw=${raw.slice(0, 160)}`)
  if (parsed.data.confidence < confidenceFloor) return abstain("confidence below configured floor")
  if (parsed.data.action !== "ACCEPT" && parsed.data.action !== "ABSTAIN" && parsed.data.citations.length === 0) {
    return abstain("non-accept decision requires citations")
  }
  return {
    action: parsed.data.action,
    ...(parsed.data.target === undefined ? {} : { target: parsed.data.target }),
    rationale: parsed.data.rationale,
    citations: parsed.data.citations,
    confidence: parsed.data.confidence,
  }
}

export type TickRequest = {
  readonly adapter: ReasoningAdapter
  readonly context: AssembledContext
  readonly target: Turn
  readonly confidenceFloor: number
}

export const POLICY = `You are the Project Supervisor for this workspace — a read-only stand-in for the human operator. You see exactly what the operator would see: top-level user messages and assistant replies. Tool output and subagent internals are hidden from you.

A worker session just completed the turn labeled TARGET below. Decide what the operator's stand-in should do.

Actions:
- ACCEPT: The exchange is COMPLETE. The reply answers what was asked; nothing further is expected. Do nothing.
- CONTINUE: The exchange is INCOMPLETE — the worker stalled at a trivial go-ahead point. Signals: it proposed next steps and asked for confirmation; it asked a question it could answer itself with the context it already has; it stopped mid-scoped-work without finishing; it asked permission for something the ongoing task already authorizes. A reasonable operator would reply "proceed", "go", or "OK". No new information, decision, or authorization is actually needed.
- STEER: The worker is proceeding on stale or contradicted information established elsewhere in the supplied context. Cite the conflicting turns.
- REFORMULATE: The reply is a final answer a cold reader cannot act on (jargon, no stated impact or required decision). Demand a rewrite: what changed, why it matters, what is asked of the operator.
- DEMAND_EXPLANATION: The MATTER ITSELF cannot be evaluated from the supplied transcript — the reply's conclusions rest on context that is not supplied (references to earlier agreements or sessions, session-internal shorthand, unexplained jargon chains, conclusions whose basis is hidden in tool state). Demand a standalone explanation built from first principles: define the terms, state what changed and when, why it matters, and what is requested — relying on nothing from the session's interior. This is not a rewrite of prose; it is a reconstruction of foundations.
- ESCALATE: A genuine operator decision is required: scope change, destructive or irreversible action, external dependency, or genuinely ambiguous intent. Describe the decision precisely.
- ABSTAIN: Insufficient evidence or confidence. Do nothing.

Decision rules:
1. CONTINUE means NO operator decision exists. If a real decision is pending, ESCALATE. If the work is simply finished, ACCEPT.
2. Use only facts from the supplied transcript. Every non-ACCEPT/ABSTAIN action must cite specific messages.
3. Sufficiency test before deciding: could a competent operator, seeing ONLY the supplied transcript, evaluate the matter at hand? If yes, decide normally. If the gap is a pending OPERATOR DECISION, ESCALATE. If the gap is foundational understanding of the matter itself, DEMAND_EXPLANATION (not ESCALATE — the operator needs the explanation before any decision can even be framed; not ABSTAIN — abstaining discards the request for the missing foundation). If the gap is mere confidence in your reading, ABSTAIN.
4. Prefer the least intrusive correct action: ACCEPT before CONTINUE before STEER/REFORMULATE before DEMAND_EXPLANATION before ESCALATE.
5. Calibrate confidence: 0.9+ only with clear textual evidence.

Return STRICT JSON only: {"action": "ACCEPT|ABSTAIN|CONTINUE|STEER|REFORMULATE|DEMAND_EXPLANATION|ESCALATE", "target": null, "rationale": "...", "citations": [{"session": "...", "messageID": "...", "quote": "..."}], "confidence": 0.0-1.0}`

export async function runTick(request: TickRequest): Promise<Decision> {
  if (request.context.truncated) return abstain("context exceeded token budget")
  const prompt = [
    POLICY,
    `TARGET SESSION ${request.target.sessionID} MESSAGE ${request.target.userMessageID}`,
    request.context.text,
  ].join("\n\n")
  try {
    return parseDecision(await request.adapter.complete(prompt), request.confidenceFloor)
  } catch (error) {
    const status = typeof error === "object" && error !== null && "status" in error && typeof error.status === "number"
      ? ` HTTP ${error.status}`
      : ""
    return abstain(`reasoning adapter failed${status}`)
  }
}
