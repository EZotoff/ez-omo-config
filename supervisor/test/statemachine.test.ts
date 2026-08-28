import { describe, expect, test } from "bun:test"
import { initialState, transition } from "../src/statemachine"

describe("session FSM", () => {
  test("advances idle through grace, tick, and decided", () => {
    const grace = transition(initialState, { type: "idle", at: 100 })
    const tick = transition(grace.state, { type: "grace_elapsed", at: 160 })
    const decided = transition(tick.state, { type: "decision_recorded", at: 161 })
    expect([grace.state.kind, tick.state.kind, decided.state.kind]).toEqual(["GRACE", "TICK", "DECIDED"])
  })

  test.each(["retry", "compaction"] as const)("parks on %s and rearms on idle", (type) => {
    const parked = transition({ kind: "GRACE", since: 1 }, { type, at: 2 })
    const rearmed = transition(parked.state, { type: "idle", at: 3 })
    expect([parked.state.kind, rearmed.state.kind]).toEqual(["PARKED", "GRACE"])
  })

  test("logs illegal transitions instead of throwing", () => {
    const result = transition(initialState, { type: "decision_recorded", at: 1 })
    expect(result.illegal).toBe(true)
    expect(result.state).toEqual(initialState)
  })
})
