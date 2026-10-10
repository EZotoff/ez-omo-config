import { describe, expect, test } from "bun:test"
import { randomUUID } from "node:crypto"
import { tmpdir } from "node:os"
import { errorSignature, investigationPrompt, InvestigationMemory, maybeDispatchErrorInvestigation, type ErrorHourState, type InvestigationConfig } from "../src/investigation"
import { Ledger } from "../src/ledger"

const ROOT = "/home/ezotoff/AI_projects/ANIA"

type Harness = ReturnType<typeof makeHarness>

function makeHarness(options: { readonly failCreate?: boolean } = {}) {
  const created: Array<{ directory: string; title: string }> = []
  const prompted: Array<{ sessionID: string; directory: string; text: string }> = []
  const appended: Array<{ type: "INTERVENTION_SENT" | "ERROR" | "INVESTIGATION_DEDUPED"; payload: Record<string, unknown> }> = []
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
  const append = async (type: "INTERVENTION_SENT" | "ERROR" | "INVESTIGATION_DEDUPED", payload: Record<string, unknown>) => {
    appended.push({ type, payload })
  }
  const config: InvestigationConfig = { enabled: true, threshold: 10 }
  const dispatch = (
    count: number,
    peak = count,
    extra: { readonly memory?: InvestigationMemory; readonly signature?: string; readonly nowMs?: number; readonly dedupWindowH?: number } = {},
  ) => maybeDispatchErrorInvestigation({ client, append, config, errorHour, root: ROOT, count, peak, ...extra })
  return { created, prompted, appended, errorHour, client, append, dispatch }
}

describe("maybeDispatchErrorInvestigation", () => {
  for (const failures of [2, 3]) {
    test(`investigation retries the existing session with ${failures} failed POSTs`, async () => {
      // Given
      const harness = makeHarness()
      const sessionIDs: string[] = []
      harness.client.promptAsync = async (sessionID) => {
        sessionIDs.push(sessionID)
        expect(harness.appended.some((entry) => entry.type === "INTERVENTION_SENT")).toBe(false)
        if (sessionIDs.length <= failures) throw new Error("POST failed")
      }
      // When
      const outcome = await harness.dispatch(10)
      // Then
      expect(harness.created).toHaveLength(1)
      expect(sessionIDs).toEqual(["ses_1", "ses_1", "ses_1"])
      expect(outcome.dispatched).toBe(failures === 2)
      expect(harness.appended.filter((entry) => entry.type === "INTERVENTION_SENT")).toHaveLength(failures === 2 ? 1 : 0)
      expect(harness.appended.filter((entry) => entry.type === "ERROR")).toHaveLength(failures)
    })
  }
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

describe("cross-hour dedup", () => {
  test("same signature within window skips dispatch, consumes the slot, and appends INVESTIGATION_DEDUPED exactly once", async () => {
    const harness = makeHarness()
    const memory = new InvestigationMemory(6)
    await memory.load(`${tmpdir()}/investigations-${randomUUID()}.json`)
    const recordedAt = 1_000_000_000_000
    await memory.record("sig-A", recordedAt)
    const first = await harness.dispatch(10, 10, { memory, signature: "sig-A", nowMs: recordedAt + 3_600_000 })
    expect(first).toEqual({ dispatched: false, reason: "already-investigated" })
    expect(harness.created).toEqual([])
    expect(harness.errorHour.investigated).toBe(true)
    const second = await harness.dispatch(11, 11, { memory, signature: "sig-A", nowMs: recordedAt + 3_600_100 })
    expect(second).toEqual({ dispatched: false, reason: "already-investigated" })
    expect(harness.created).toEqual([])
    const deduped = harness.appended.filter((entry) => entry.type === "INVESTIGATION_DEDUPED")
    expect(deduped).toHaveLength(1)
    expect(deduped[0]?.payload).toEqual({ root: ROOT, signature: "sig-A", windowH: 6 })
  })

  test("different signature dispatches and records the fingerprint", async () => {
    const harness = makeHarness()
    const memory = new InvestigationMemory(6)
    const path = `${tmpdir()}/investigations-${randomUUID()}.json`
    await memory.load(path)
    await memory.record("sig-A", 1_000_000_000_000)
    const outcome = await harness.dispatch(10, 10, { memory, signature: "sig-B", nowMs: 1_000_000_000_000 + 60_000 })
    expect(outcome.dispatched).toBe(true)
    expect(harness.created).toHaveLength(1)
    expect(memory.recentlyDispatched("sig-B", 1_000_000_000_000 + 120_000)).toBe(true)
  })

  test("same signature after the window expires dispatches again", async () => {
    const harness = makeHarness()
    const memory = new InvestigationMemory(6)
    await memory.load(`${tmpdir()}/investigations-${randomUUID()}.json`)
    const recordedAt = 1_000_000_000_000
    await memory.record("sig-A", recordedAt)
    const outcome = await harness.dispatch(10, 10, { memory, signature: "sig-A", nowMs: recordedAt + 7 * 3_600_000 })
    expect(outcome.dispatched).toBe(true)
    expect(harness.created).toHaveLength(1)
  })
})

describe("errorSignature", () => {
  test("normalizes ses IDs and caps at 120 chars", () => {
    expect(errorSignature("opencode client failed: /session/ses_abc123/message ...")).toBe("opencode client failed: /session/ses_*/message ...")
    expect(errorSignature("y".repeat(200))).toHaveLength(120)
  })
})

describe("InvestigationMemory", () => {
  test("round-trips fingerprints across a fresh instance", async () => {
    const path = `${tmpdir()}/investigations-${randomUUID()}.json`
    const memory = new InvestigationMemory(6)
    await memory.load(path)
    const now = 1_000_000_000_000
    expect(memory.recentlyDispatched("sig", now)).toBe(false)
    await memory.record("sig", now)
    const fresh = new InvestigationMemory(6)
    await fresh.load(path)
    expect(fresh.recentlyDispatched("sig", now)).toBe(true)
    expect(fresh.recentlyDispatched("sig", now + 7 * 3_600_000)).toBe(false)
  })
})

describe("ledger schema", () => {
  test("Ledger appends and re-reads INVESTIGATION_DEDUPED with type intact", async () => {
    const path = `${tmpdir()}/ledger-${randomUUID()}.jsonl`
    let ledger = await Ledger.open(path)
    ledger = await ledger.append("INVESTIGATION_DEDUPED", { root: ROOT, signature: "sig-A", windowH: 6 })
    const reopened = await Ledger.open(path)
    expect(reopened.records.at(-1)?.type).toBe("INVESTIGATION_DEDUPED")
    expect(reopened.records).toHaveLength(1)
  })
})
