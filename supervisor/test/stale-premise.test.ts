// Episode-token stale-premise guard (F1 D4, 2026-10-10). The end-of-tick
// decision write must not clobber a newer episode that landed during the
// tick's awaits; it records TICK_STALE_PREMISE instead.
import { afterEach, describe, expect, test } from "bun:test"
import { mkdtemp, rm } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { Ledger } from "../src/ledger"
import { recordDecisionGuarded } from "../src/service"
import { initialState, transition, type SessionState } from "../src/statemachine"

const paths: string[] = []
afterEach(async () => Promise.all(paths.splice(0).map((path) => rm(path, { recursive: true, force: true }))))

async function harness(): Promise<{ ledger: Ledger; states: Map<string, SessionState>; tick: SessionState }> {
  const directory = await mkdtemp(join(tmpdir(), "supervisor-stale-")); paths.push(directory)
  const ledger = await Ledger.open(join(directory, "ledger.jsonl"))
  const states = new Map<string, SessionState>()
  const grace = transition(initialState, { type: "idle", at: 1 }).state
  const tick = transition(grace, { type: "grace_elapsed", at: 2 }).state
  states.set("ses_1", tick)
  return { ledger, states, tick }
}

describe("recordDecisionGuarded", () => {
  test("writes decision_recorded when the episode is unchanged", async () => {
    const { ledger, states, tick } = await harness()
    const next = await recordDecisionGuarded(ledger, states, "ses_1", tick, "/root", 3)
    expect(states.get("ses_1")?.kind).toBe("DECIDED")
    expect(next.records.filter((record) => record.type === "TICK_STALE_PREMISE")).toHaveLength(0)
  })

  test("a newer event during the tick await is not overwritten; TICK_STALE_PREMISE recorded", async () => {
    const { ledger, states, tick } = await harness()
    // Simulate a newer event landing during the tick await: the session went
    // busy, replacing the captured TICK object with a fresh IDLE state.
    const newer = transition(tick, { type: "busy", at: 3 }).state
    expect(newer).not.toBe(tick)
    states.set("ses_1", newer)

    const next = await recordDecisionGuarded(ledger, states, "ses_1", tick, "/root", 4)

    expect(states.get("ses_1")).toBe(newer) // newer episode untouched
    const stale = next.records.filter((record) => record.type === "TICK_STALE_PREMISE")
    expect(stale).toHaveLength(1)
    expect((stale[0]?.payload as { readonly sessionID: string }).sessionID).toBe("ses_1")
  })
})
