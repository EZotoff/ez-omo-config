import { z } from "zod"
import type { Decision, Turn } from "./types"
import type { ReasoningAdapter } from "./adapter"
import type { AssembledContext } from "./assembler"

const citationSchema = z.object({ session: z.string().min(1), messageID: z.string().min(1), quote: z.string().min(1) }).strict()
const decisionSchema = z.object({
  action: z.enum(["ACCEPT", "ABSTAIN", "CONTINUE", "STEER", "REFORMULATE", "ESCALATE"]),
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
      ? "REFORMULATE"
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
- CONTINUE: The exchange is INCOMPLETE and the worker needs only a trivial go-ahead. Two trigger classes: (a) APPROVE — the worker proposed next steps and asked "shall I?"; a reasonable operator replies "proceed"/"go"/"OK". (b) KICK-START — the session stalled, errored, or died after a restart and produced no reply; a reasonable operator replies "continue". The operator's word "continue" means kick-start; "proceed" means approve — never read an operator "continue" as approval of proposed next steps. No new information, decision, or authorization is needed in either case.
- STEER: The worker is proceeding on stale or contradicted information established elsewhere in the supplied context. Cite the conflicting turns.
- REFORMULATE: The reply cannot be evaluated or acted on by a competent operator seeing only the supplied transcript. Two shapes: (a) a final answer that is all jargon, with no stated impact and no required decision; (b) a reply whose conclusions rest on context that is NOT supplied — references to earlier agreements or sessions, session-internal shorthand, unexplained jargon chains, bases hidden in tool state. In shape (b) demand a standalone account rebuilt from first principles: define the terms, state what changed and when, why it matters, and what is requested — relying on nothing from the session's interior.
- ESCALATE: A genuine operator decision is required: scope change, destructive or irreversible action, external dependency, or genuinely ambiguous intent. Describe the decision precisely.
- ABSTAIN: Insufficient evidence or confidence. Do nothing.

Decision rules:
1. CONTINUE means NO operator decision exists. If a real decision is pending, ESCALATE. If the work is simply finished, ACCEPT.
2. Use only facts from the supplied transcript. Every non-ACCEPT/ABSTAIN action must cite specific messages.
3. Sufficiency test before deciding: could a competent operator, seeing ONLY the supplied transcript, evaluate the matter at hand? If the gap is a pending OPERATOR DECISION, ESCALATE. If the gap is understanding the matter itself — opacity, missing foundations, context that was never supplied — REFORMULATE with an explicit demand for a standalone account built from first principles. If the gap is mere confidence in your reading, ABSTAIN.
4. Prefer the least intrusive correct action: ACCEPT before CONTINUE before STEER/REFORMULATE before ESCALATE.
5. Calibrate confidence: 0.9+ only with clear textual evidence.
6. Read operator messages for INTENT, not literal text. The intent behind an instruction outweighs its literal wording. Before acting on a literal reading, check it against the rest of the same message and the session's purpose. If the literal reading contradicts its own context — a probable typo that reverses meaning, or an instruction paired with a question that presupposes the opposite — do NOT act on the literal reading: ACCEPT if the worker already resolved it correctly, ESCALATE if a real decision pends. Never CONTINUE on a reading that rests on a probable typo or self-contradiction.
7. CONTINUE is legal ONLY when the session is quiescent — nothing is in flight (no tool, command, or subagent running; the session is not busy). A running session needs no nudge. When in doubt, ABSTAIN.
8. A question is an INFORMATION request only if the operator needs the answer to make a decision. A question that provokes the worker's own reasoning ("why would X be the case?", "what is the purpose of Y?") is a thinking-prompt, not an info request — do not ESCALATE for it.
9. Deployment, promote, prod-write, and credential decisions are ESCALATE by default. Exception: if the project's trust config marks deploys autonomous, treat them as ordinary work.
10. L1 TARGET HISTORY contains this session's prior turns — it is your memory. Use it to resolve ambiguous references, detect contradictions, and honor decisions already made earlier in the session.
11. Your recent decisions and open tickets for this session are provided. Do not repeat a decision on the same unresolved cause. If you CONTINUEd last turn and the worker still has not delivered, STEER with the specific correction.

Return STRICT JSON only: {"action": "ACCEPT|ABSTAIN|CONTINUE|STEER|REFORMULATE|ESCALATE", "target": null, "rationale": "...", "citations": [{"session": "...", "messageID": "...", "quote": "..."}], "confidence": 0.0-1.0}`

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
