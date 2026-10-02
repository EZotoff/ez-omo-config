import { describe, expect, test } from "bun:test"
import { continueCapKey, continueWriteText, gateContinueWrite, gateReformulateWrite, gateSteerWrite, reformulateWriteText, steerWriteText } from "../src/continue-writes"

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

describe("gateSteerWrite", () => {
  const steer = (citations: { session: string; quote: string }[]) => ({
    decision: { action: "STEER" as const, rationale: "reconcile with the sibling finding", citations },
    config: { enabled: true, dailyCap: 3 },
    capUsedToday: 0,
    lastMessageID: "a1",
    target: { assistantMessageID: "a1", sessionID: "ses_target" },
    sessionProtected: false,
  })

  test("allows STEER with a non-target citation and intact premise", () => {
    const gate = gateSteerWrite(steer([{ session: "ses_sibling", quote: "Redis was removed for ordering bugs" }]))
    expect(gate).toEqual({ allowed: true })
  })
  test("blocks target-only citations (cross-session evidence is STEER's justification)", () => {
    const gate = gateSteerWrite(steer([{ session: "ses_target", quote: "local evidence only" }]))
    expect(gate.allowed).toBe(false)
    if (!gate.allowed) expect(gate.reason).toContain("outside the target session")
  })
  test("blocks on premise change", () => {
    const input = steer([{ session: "ses_sibling", quote: "fact" }])
    const gate = gateSteerWrite({ ...input, lastMessageID: "newer-push" })
    expect(gate.allowed).toBe(false)
  })
  test("blocks on cap", () => {
    const gate = gateSteerWrite({ ...steer([{ session: "s", quote: "f" }]), capUsedToday: 3 })
    expect(gate.allowed).toBe(false)
  })
  test("blocks when disabled or protected", () => {
    expect(gateSteerWrite({ ...steer([{ session: "s", quote: "f" }]), config: { enabled: false, dailyCap: 3 } }).allowed).toBe(false)
    expect(gateSteerWrite({ ...steer([{ session: "s", quote: "f" }]), sessionProtected: true }).allowed).toBe(false)
  })
  test("steerWriteText is visible and carries the guidance", () => {
    const t = steerWriteText({ rationale: "reconcile with A/13 before proceeding" })
    expect(t.startsWith("[supervisor] (steer)")).toBe(true)
    expect(t).toContain("reconcile with A/13")
  })
})

/* --- Stall detection (poller) — regression fixture: the 2026-09-20 wedged glm-5.3-flash turn --- */
test("poller emits stalled once for an incomplete turn quiescent past the threshold", async () => {
  const { pollRootOnce } = await import("../src/poller")
  const { OpencodeClient } = await import("../src/client")
  const c = new OpencodeClient("http://127.0.0.1:1", undefined) // never reached — HTTP stubbed below
  const origFetch = globalThis.fetch
  let calls = 0
  globalThis.fetch = (async () => {
    calls += 1
    if (calls % 2 === 1) {
      return new Response(JSON.stringify([{ id: "ses_wedge", directory: "/root", time: { updated: 1_000_000 } }]), { status: 200 })
    }
    return new Response(JSON.stringify([
      { info: { id: "u1", sessionID: "ses_wedge", role: "user", time: { created: 999_000 } }, parts: [{ id: "p1", messageID: "u1", type: "text", text: "go" }] },
      { info: { id: "a1", sessionID: "ses_wedge", role: "assistant", time: { created: 1_000_000 } }, parts: [{ id: "p2", messageID: "a1", type: "step-start" }] },
    ]), { status: 200 })
  }) as unknown as typeof fetch
  try {
    const prev = new Map()
    // First poll inside the recent-activity window (session becomes tracked, incomplete turn);
    // second poll past the stall threshold — session now outside the activity
    // window but tracked: exactly the stall-eligibility case the window filter broke.
    const s1 = await pollRootOnce(c, "/root", new Set(), prev, 1_000_000 + 14 * 60_000, 15 * 60_000)
    const s2 = await pollRootOnce(c, "/root", new Set(), prev, 1_000_000 + 21 * 60_000, 15 * 60_000)
    const kinds1 = s1.filter((x) => x.sessionID === "ses_wedge").map((x) => x.kind)
    const kinds2 = s2.filter((x) => x.sessionID === "ses_wedge").map((x) => x.kind)
    expect(kinds1).toContain("busy") // first observation of an incomplete turn
    expect(kinds2).toContain("stalled") // fires once quiescent past the threshold
  } finally {
    globalThis.fetch = origFetch
  }
})

test("poller does not stall healthy completed sessions", async () => {
  const { pollRootOnce } = await import("../src/poller")
  const { OpencodeClient } = await import("../src/client")
  const c = new OpencodeClient("http://127.0.0.1:1", undefined)
  const origFetch = globalThis.fetch
  let calls = 0
  globalThis.fetch = (async () => {
    calls += 1
    if (calls % 2 === 1) {
      return new Response(JSON.stringify([{ id: "ses_ok", directory: "/root", time: { updated: 1_000_000 } }]), { status: 200 })
    }
    return new Response(JSON.stringify([
      { info: { id: "u1", sessionID: "ses_ok", role: "user", time: { created: 999_000 } }, parts: [{ id: "p1", messageID: "u1", type: "text", text: "go" }] },
      { info: { id: "a1", sessionID: "ses_ok", role: "assistant", time: { created: 1_000_000, completed: 1_000_500 } }, parts: [{ id: "p2", messageID: "a1", type: "text", text: "done" }] },
    ]), { status: 200 })
  }) as unknown as typeof fetch
  try {
    const prev = new Map()
    const s1 = await pollRootOnce(c, "/root", new Set(), prev, 1_000_000 + 60 * 60_000, 15 * 60_000)
    expect(s1.filter((x) => x.sessionID === "ses_ok" && x.kind === "stalled")).toHaveLength(0)
  } finally {
    globalThis.fetch = origFetch
  }
})

describe("reformulate gate + text (2026-10-02: fresh-explain capability wired)", () => {
  const base = {
    config: { enabled: true, dailyCap: 3 },
    capUsedToday: 0,
    lastMessageID: "a1",
    target: { assistantMessageID: "a1" },
    sessionProtected: false,
  }
  test("allows when premises hold", () => expect(gateReformulateWrite(base)).toEqual({ allowed: true }))
  test("blocks disabled, protected, capped, premise-changed", () => {
    expect(gateReformulateWrite({ ...base, config: { ...base.config, enabled: false } }).allowed).toBe(false)
    expect(gateReformulateWrite({ ...base, sessionProtected: true }).allowed).toBe(false)
    expect(gateReformulateWrite({ ...base, capUsedToday: 3 }).allowed).toBe(false)
    expect(gateReformulateWrite({ ...base, lastMessageID: "newer" }).allowed).toBe(false)
  })
  test("write text demands a standalone first-principles account", () => {
    const t = reformulateWriteText({ rationale: "all jargon, no stated impact" })
    expect(t.startsWith("[supervisor] (reformulate)")).toBe(true)
    expect(t).toContain("first principles")
    expect(t).toContain("all jargon")
  })
})
