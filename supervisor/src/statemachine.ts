import { assertNever } from "./types"

export type SessionState =
  | { readonly kind: "IDLE" }
  | { readonly kind: "GRACE"; readonly since: number }
  | { readonly kind: "TICK"; readonly since: number }
  | { readonly kind: "DECIDED"; readonly since: number }
  | { readonly kind: "PARKED"; readonly reason: "retry" | "compaction"; readonly since: number }

export type SessionEvent =
  | { readonly type: "idle"; readonly at: number }
  | { readonly type: "busy"; readonly at: number }
  | { readonly type: "retry"; readonly at: number }
  | { readonly type: "compaction"; readonly at: number }
  | { readonly type: "grace_elapsed"; readonly at: number }
  | { readonly type: "decision_recorded"; readonly at: number }

export type TransitionResult = { readonly state: SessionState; readonly illegal: boolean }
export const initialState: SessionState = { kind: "IDLE" }

export function transition(state: SessionState, event: SessionEvent): TransitionResult {
  if (event.type === "retry" || event.type === "compaction") {
    return { state: { kind: "PARKED", reason: event.type, since: event.at }, illegal: false }
  }
  if (event.type === "busy") return { state: initialState, illegal: false }
  switch (state.kind) {
    case "IDLE":
      return event.type === "idle"
        ? { state: { kind: "GRACE", since: event.at }, illegal: false }
        : { state, illegal: true }
    case "GRACE":
      if (event.type === "grace_elapsed") return { state: { kind: "TICK", since: event.at }, illegal: false }
      if (event.type === "idle") return { state, illegal: false }
      return { state, illegal: true }
    case "TICK":
      return event.type === "decision_recorded"
        ? { state: { kind: "DECIDED", since: event.at }, illegal: false }
        : { state, illegal: true }
    case "DECIDED":
      return event.type === "idle"
        ? { state: { kind: "GRACE", since: event.at }, illegal: false }
        : { state, illegal: true }
    case "PARKED":
      return event.type === "idle"
        ? { state: { kind: "GRACE", since: event.at }, illegal: false }
        : { state, illegal: true }
    default:
      return assertNever(state)
  }
}
