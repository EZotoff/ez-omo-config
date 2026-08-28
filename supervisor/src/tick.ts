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
  const actionUpper = typeof actionRaw === "string" ? actionRaw.toUpperCase().replace(/[ -]/g, "_") : actionRaw
  const action = actionUpper === "NONE" || actionUpper === "NOOP" || actionUpper === "NO_OP" || actionUpper === "DO_NOTHING"
    ? "ACCEPT"
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

export async function runTick(request: TickRequest): Promise<Decision> {
  if (request.context.truncated) return abstain("context exceeded token budget")
  const prompt = [
    "You are a read-only project supervisor. Judge only the supplied human-visible transcript.",
    "Return strict JSON with action, optional target, rationale, citations, and confidence. Use zero tools.",
    `TARGET SESSION ${request.target.sessionID} MESSAGE ${request.target.userMessageID}`,
    request.context.text,
  ].join("\n\n")
  return parseDecision(await request.adapter.complete(prompt), request.confidenceFloor)
}
