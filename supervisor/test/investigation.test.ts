import { describe, expect, test } from "bun:test"
import { investigationPrompt, maybeDispatchErrorInvestigation, type ErrorHourState, type InvestigationConfig } from "../src/investigation"

const ROOT = "/home/ezotoff/AI_projects/ANIA"

type Harness = ReturnType<typeof makeHarness>

function makeHarness(options: { readonly failCreate?: boolean } = {}) {
  const created: Array<{ directory: string; title: string }> = []
  const prompted: Array<{ sessionID: string; directory: string; text: string }> = []
  const appended: Array<{ type: "INTERVENTION_SENT" | "ERROR"; payload: Record<string, unknown> }> = []
  const errorHour: ErrorHourState = { windowStart: Date.now(), count: 0, toasted: false, investigated: false }
  const client = {
    createSession: async (directory: string, title: string) => {
      if (options.failCreate === true) throw new Error("session create boom")
      created.push({ directory, title })
      return { id: `ses_${created.length}`, directory }
    },
    promptAsync: async (sessionID: string, directory: string, text: string) => {
      prompted.push({ sessionID, directory, text })
    },
  }
  const append = async (type: "INTERVENTION_SENT" | "ERROR", payload: Record<string, unknown>) => {
    appended.push({ type, payload })
  }
  const config: InvestigationConfig = { enabled: true, threshold: 10 }
  const dispatch = (count: number, peak = count) =>
    maybeDispatchErrorInvestigation({ client, append, config, errorHour, root: ROOT, count, peak })
  return { created, prompted, appended, errorHour, client, append, dispatch }
}

describe("maybeDispatchErrorInvestigation", () => {
  test("disabled config never dispatches, even above threshold", async () => {
    const harness = makeHarness()
    harness.errorHour.investigated = false
    const outcome = await maybeDispatchErrorInvestigation({
      client: harness.client,
      append: harness.append,
      config: { enabled: false, threshold: 10 },
      errorHour: harness.errorHour,
      root: ROOT,
      count: 50,
      peak: 50,
    })
    expect(outcome).toEqual({ dispatched: false, reason: "disabled" })
    expect(harness.created).toEqual([])
  })

  test("below threshold does not dispatch and leaves the window slot free", async () => {
    const harness = makeHarness()
    const outcome = await harness.dispatch(9)
    expect(outcome).toEqual({ dispatched: false, reason: "below-threshold" })
    expect(harness.created).toEqual([])
    expect(harness.errorHour.investigated).toBe(false)
  })

  test("crossing the threshold creates the session, prompts it, and logs INTERVENTION_SENT", async () => {
    const harness = makeHarness()
    const outcome = await harness.dispatch(10, 12)
    expect(outcome.dispatched).toBe(true)
    if (outcome.dispatched) {
      expect(outcome.sessionID).toBe("ses_1")
    }
    expect(harness.created).toEqual([{ directory: ROOT, title: "[Supervisor] error investigation (ANIA)" }])
    expect(harness.prompted).toHaveLength(1)
    expect(harness.prompted[0]?.sessionID).toBe("ses_1")
    expect(harness.prompted[0]?.text).toContain("10 errors")
    expect(harness.appended).toEqual([{
      type: "INTERVENTION_SENT",
      payload: { mode: "investigation", root: ROOT, sessionID: "ses_1", count: 10, peak: 12, threshold: 10 },
    }])
    expect(harness.errorHour.investigated).toBe(true)
  })

  test("a second crossing in the same window does not re-dispatch", async () => {
    const harness = makeHarness()
    await harness.dispatch(10)
    const second = await harness.dispatch(11)
    expect(second).toEqual({ dispatched: false, reason: "already-investigated" })
    expect(harness.created).toHaveLength(1)
  })

  test("failed session creation consumes the window slot, logs ERROR, and never prompts", async () => {
    const harness = makeHarness({ failCreate: true })
    const outcome = await harness.dispatch(10)
    expect(outcome).toEqual({ dispatched: false, reason: "dispatch-failed", error: "session create boom" })
    expect(harness.prompted).toEqual([])
    expect(harness.appended).toEqual([{
      type: "ERROR",
      payload: { root: ROOT, reason: "error investigation dispatch failed: session create boom" },
    }])
    expect(harness.errorHour.investigated).toBe(true)
  })
})

describe("investigationPrompt", () => {
  test("carries the supervisor tag, counts, and the two evidence sources", () => {
    const prompt = investigationPrompt(ROOT, 11, 12, 10)
    expect(prompt.startsWith("[Supervisor]")).toBe(true)
    expect(prompt).toContain("11 errors")
    expect(prompt).toContain("peak 12")
    expect(prompt).toContain("ledger.jsonl")
    expect(prompt).toContain("journalctl")
  })
})
