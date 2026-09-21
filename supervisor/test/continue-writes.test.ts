import { describe, expect, test } from "bun:test"
import { continueCapKey, continueWriteText, gateContinueWrite } from "../src/continue-writes"

const base = {
  config: { enabled: true, dailyCap: 5, kickStartOnly: true },
  capUsedToday: 0,
  lastMessageID: "a1" as string | undefined,
  sessionProtected: false,
}
const target = { assistantMessageID: "a1" }
const dec = (mode: "kick_start" | "approve" | null) => ({ action: "CONTINUE" as const, mode, rationale: "stalled" })

describe("gateContinueWrite", () => {
  test("allows a kick_start CONTINUE when all premises hold", () => {
    expect(gateContinueWrite({ ...base, decision: dec("kick_start"), target })).toEqual({ allowed: true })
  })
  test("disabled root blocks", () => {
    expect(gateContinueWrite({ ...base, config: { ...base.config, enabled: false }, decision: dec("kick_start"), target }).allowed).toBe(false)
  })
  test("protected session blocks", () => {
    expect(gateContinueWrite({ ...base, decision: dec("kick_start"), target, sessionProtected: true }).allowed).toBe(false)
  })
  test("cap blocks", () => {
    const gate = gateContinueWrite({ ...base, decision: dec("kick_start"), target, capUsedToday: 5 })
    expect(gate.allowed).toBe(false)
    if (!gate.allowed) expect(gate.reason).toContain("cap")
  })
  test("kick_start-only blocks approve and unspecified modes", () => {
    for (const mode of ["approve", null] as const) {
      const gate = gateContinueWrite({ ...base, decision: dec(mode), target })
      expect(gate.allowed).toBe(false)
      if (!gate.allowed) expect(gate.reason).toContain("kick_start")
    }
  })
  test("kick_start-only=false permits approve mode", () => {
    const gate = gateContinueWrite({ ...base, config: { ...base.config, kickStartOnly: false }, decision: dec("approve"), target })
    expect(gate.allowed).toBe(true)
  })
  test("premise change (newer message after target reply) blocks", () => {
    const gate = gateContinueWrite({ ...base, decision: dec("kick_start"), target: { assistantMessageID: "a1" }, lastMessageID: "ralph-push" })
    expect(gate.allowed).toBe(false)
    if (!gate.allowed) expect(gate.reason).toContain("premise changed")
  })
  test("missing last message id blocks", () => {
    expect(gateContinueWrite({ ...base, decision: dec("kick_start"), target, lastMessageID: undefined }).allowed).toBe(false)
  })
})

describe("continueWriteText", () => {
  test("visible [supervisor] prefix, generic kick-start phrasing", () => {
    const t = continueWriteText({ rationale: "whatever" })
    expect(t.startsWith("[supervisor]")).toBe(true)
    expect(t).toContain("continue")
  })
})

describe("continueCapKey", () => {
  test("date-scoped key resets daily", () => {
    expect(continueCapKey(new Date("2026-09-21T23:59:59Z"))).toBe("2026-09-21")
  })
})
