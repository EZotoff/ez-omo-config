import { describe, expect, test } from "bun:test"
import { canOpenTicket, type ConsoleState } from "../src/console"

const base: ConsoleState = { consoles: {}, counters: {}, openTickets: [] }

describe("canOpenTicket", () => {
  test("allows a first ticket for a session", () => {
    expect(canOpenTicket(base, "/root", "ses-a").ok).toBe(true)
  })
  test("suppresses a second open ticket for the same session", () => {
    const state: ConsoleState = { ...base, openTickets: [{ id: "Q1", n: 1, root: "/root", sessionID: "ses-a", question: "q", createdAt: "t" }] }
    expect(canOpenTicket(state, "/root", "ses-a")).toMatchObject({ ok: false })
  })
  test("enforces the per-root open-ticket cap", () => {
    const open = [1, 2, 3, 4, 5].map((n): ConsoleState["openTickets"][number] => ({ id: `Q${n}`, n, root: "/root", sessionID: `ses-${n}`, question: "q", createdAt: "t" }))
    expect(canOpenTicket({ ...base, openTickets: open }, "/root", "ses-new")).toMatchObject({ ok: false, reason: expect.stringContaining("cap") })
  })
  test("cap is per-root", () => {
    const open = [1, 2, 3, 4, 5].map((n): ConsoleState["openTickets"][number] => ({ id: `Q${n}`, n, root: "/other", sessionID: `ses-${n}`, question: "q", createdAt: "t" }))
    expect(canOpenTicket({ ...base, openTickets: open }, "/root", "ses-a").ok).toBe(true)
  })
})
