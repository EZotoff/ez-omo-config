import type { Decision } from "./types"

type ContinueMode = "kick_start" | "approve" | null

export type ContinueWriteConfig = {
  readonly enabled: boolean
  readonly dailyCap: number
  readonly kickStartOnly: boolean
}

export type ContinueWriteGateInput = {
  readonly decision: { readonly action: Decision["action"]; readonly mode?: ContinueMode }
  readonly config: ContinueWriteConfig
  readonly capUsedToday: number
  readonly lastMessageID: string | undefined
  readonly target: { readonly assistantMessageID?: string }
  readonly sessionProtected: boolean
}

export type ContinueWriteGate =
  | { readonly allowed: true }
  | { readonly allowed: false; readonly reason: string }

/**
 * CONTINUE is the only intervention that writes into a worker session, and only
 * under this gate (operator-approved 2026-09-21, ez-omo-bench first):
 * - root config enables it (daily cap bounds blast radius),
 * - the action is CONTINUE with kick_start mode (or unspecified-when-kick-start-only is off),
 * - the premise still holds: the target reply is STILL the session's last message
 *   (no ralph push, no newer turn since the decision),
 * - the session is not operator-protected,
 * - the daily cap has headroom.
 */
export function gateContinueWrite(input: ContinueWriteGateInput): ContinueWriteGate {
  if (!input.config.enabled) return { allowed: false, reason: "continue writes disabled for this root" }
  if (input.sessionProtected) return { allowed: false, reason: "session is operator-protected" }
  if (input.decision.action !== "CONTINUE") return { allowed: false, reason: "action is not CONTINUE" }
  if (input.capUsedToday >= input.config.dailyCap) {
    return { allowed: false, reason: `daily continue cap reached (${input.config.dailyCap})` }
  }
  if (input.config.kickStartOnly && input.decision.mode !== "kick_start") {
    return { allowed: false, reason: `kick_start-only gate: decision mode was ${String(input.decision.mode)}` }
  }
  if (input.lastMessageID === undefined || input.target.assistantMessageID !== input.lastMessageID) {
    return { allowed: false, reason: "premise changed before write: newer message after target reply" }
  }
  return { allowed: true }
}

export function continueWriteText(decision: Pick<Decision, "rationale">): string {
  return `[supervisor] (continue) You appear to have stalled mid-task — please continue with the current work.`
}

export function continueCapKey(now: Date): string {
  return now.toISOString().slice(0, 10)
}

export type SteerWriteConfig = {
  readonly enabled: boolean
  readonly dailyCap: number
}

export type SteerWriteGateInput = {
  readonly decision: { readonly action: Decision["action"]; readonly rationale: string; readonly citations: readonly { readonly session: string; readonly quote: string }[] }
  readonly config: SteerWriteConfig
  readonly capUsedToday: number
  readonly lastMessageID: string | undefined
  readonly target: { readonly assistantMessageID?: string; readonly sessionID: string }
  readonly sessionProtected: boolean
}

/**
 * STEER carries substantive cross-session guidance into a worker session — a wrong
 * steer misdirects work, so the gate adds one CONTINUE does not have: at least one
 * citation must come from OUTSIDE the target session (cross-session evidence is
 * STEER's whole justification).
 */
export function gateSteerWrite(input: SteerWriteGateInput): ContinueWriteGate {
  if (!input.config.enabled) return { allowed: false, reason: "steer writes disabled for this root" }
  if (input.sessionProtected) return { allowed: false, reason: "session is operator-protected" }
  if (input.decision.action !== "STEER") return { allowed: false, reason: "action is not STEER" }
  if (input.capUsedToday >= input.config.dailyCap) {
    return { allowed: false, reason: `daily steer cap reached (${input.config.dailyCap})` }
  }
  if (input.lastMessageID === undefined || input.target.assistantMessageID !== input.lastMessageID) {
    return { allowed: false, reason: "premise changed before write: newer message after target reply" }
  }
  const nonTarget = input.decision.citations.some((c) => c.session !== input.target.sessionID)
  if (!nonTarget) {
    return { allowed: false, reason: "STEER requires at least one citation outside the target session" }
  }
  return { allowed: true }
}

export function steerWriteText(decision: Pick<Decision, "rationale">): string {
  return `[supervisor] (steer) ${decision.rationale.slice(0, 600)}`
}
