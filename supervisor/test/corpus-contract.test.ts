import { existsSync } from "node:fs"
import { readFileSync } from "node:fs"
import { homedir } from "node:os"
import { join } from "node:path"
import { describe, expect, test } from "bun:test"
import { contiguousAssistantRun, messageText, projectTurns } from "../src/projector"
import { extractExchange } from "../src/replay"
import { ACTIONS } from "../src/types"
import type { Message } from "../src/types"

const GRADING_DIR = join(homedir(), ".local", "state", "opencode-supervisor", "grading")

const msg = (id: string, role: "user" | "assistant", parts: readonly Message["parts"][number][], sessionID = "ses_contract"): Message => ({
  id,
  sessionID,
  role,
  time: { created: 1 },
  parts,
})

const textPart = (id: string, text: string): Message["parts"][number] => ({ id, messageID: id.slice(0, -1), type: "text", text })

// Fixture shape: assistant run = [reasoning-only, tool-only, text] — the exact
// 31/217 corpus bug class where messages[i+1] carries no text.
const multiMessageRun: readonly Message[] = [
  msg("u1", "user", [textPart("p1", "proceed with the migration")]),
  msg("a1", "assistant", [{ id: "p2", messageID: "a1", type: "reasoning" }]),
  msg("a2", "assistant", [{ id: "p3", messageID: "a2", type: "tool", tool: "bash" }]),
  msg("a3", "assistant", [textPart("p4", "Migration complete: 14 rows moved, indexes rebuilt.")]),
]

describe("extraction contract", () => {
  test("joins ALL contiguous assistant messages after the target user message", () => {
    const exchange = extractExchange(multiMessageRun, "u1", "proceed with the migration")
    expect(exchange?.workerText).toBe("Migration complete: 14 rows moved, indexes rebuilt.")
    expect(exchange?.assistantMessageIDs).toEqual(["a1", "a2", "a3"])
  })

  test("worker field is non-empty whenever the assistant run has text", () => {
    const exchange = extractExchange(multiMessageRun, "u1", "proceed with the migration")
    expect(exchange !== undefined && exchange.workerText.trim() !== "").toBe(true)
  })

  test("worker field is empty when the assistant run has no text anywhere", () => {
    const noText: readonly Message[] = [
      msg("u1", "user", [textPart("p1", "go")]),
      msg("a1", "assistant", [{ id: "p2", messageID: "a1", type: "tool", tool: "bash" }]),
    ]
    expect(extractExchange(noText, "u1", "go")?.workerText).toBe("")
  })

  test("quote-match fallback recovers the exchange when messageID lookup fails (D211 shape)", () => {
    const exchange = extractExchange(multiMessageRun, "msg-gone", "proceed with the migration")
    expect(exchange?.userMessageID).toBe("u1")
    expect(exchange?.workerText).toBe("Migration complete: 14 rows moved, indexes rebuilt.")
  })

  test("returns undefined when neither id nor quote matches", () => {
    expect(extractExchange(multiMessageRun, "msg-gone", "no such text anywhere")).toBeUndefined()
  })

  test("session ids pass through verbatim — never truncated", () => {
    const longID = "ses_f44770ae1ffe53DJY9NQyu3wWD_partition_0123456789abcdef"
    const withLongID = multiMessageRun.map((m) => ({ ...m, sessionID: longID }))
    const exchange = extractExchange(withLongID, "u1", "proceed with the migration")
    expect(exchange?.sessionID).toBe(longID)
  })

  test("projectTurns joins the contiguous run too (live replay path)", () => {
    const turns = projectTurns(multiMessageRun, { humanMessageIDs: new Set(["u1"]), supervisorMessageIDs: new Set() })
    expect(turns[0]?.assistantText).toBe("Migration complete: 14 rows moved, indexes rebuilt.")
    expect(turns[0]?.assistantMessageID).toBe("a3")
    expect(turns[0]?.transcript).toBe("USER: proceed with the migration\nASSISTANT: Migration complete: 14 rows moved, indexes rebuilt.")
  })

  test("consecutive user messages keep per-user assignment", () => {
    const twoUsers: readonly Message[] = [
      msg("u1", "user", [textPart("p1", "first")]),
      msg("u2", "user", [textPart("p2", "second")]),
      msg("a1", "assistant", [textPart("p3", "reply to second")]),
    ]
    const turns = projectTurns(twoUsers, { humanMessageIDs: new Set(["u1", "u2"]), supervisorMessageIDs: new Set() })
    expect(turns.map((t) => [t.userText, t.assistantText])).toEqual([
      ["first", ""],
      ["second", "reply to second"],
    ])
  })

  test("helpers agree: contiguousAssistantRun + messageText", () => {
    expect(contiguousAssistantRun(multiMessageRun, 0).map(messageText)).toEqual(["", "", "Migration complete: 14 rows moved, indexes rebuilt."])
    expect(contiguousAssistantRun(multiMessageRun, 4)).toEqual([])
  })
})

describe("corpus contract (live grading dir)", () => {
  test("repaired corpus items have non-empty worker evidence", () => {
    const path = join(GRADING_DIR, "repaired-items.json")
    if (!existsSync(path)) return
    const items = JSON.parse(readFileSync(path, "utf8")) as readonly { id: string; worker?: string }[]
    expect(items.length).toBeGreaterThan(0)
    for (const item of items) {
      expect((item.worker ?? "").trim() !== "").toBe(true)
    }
  })

  test("every action value in batches and repaired items is in the rubric set", () => {
    const rubricActions = new Set<string>(ACTIONS)
    const files = [join(GRADING_DIR, "repaired-items.json"), ...range1to15().map((n) => join(GRADING_DIR, `batch-${String(n).padStart(2, "0")}.json`))]
    const existing = files.filter((f) => existsSync(f))
    expect(existing.length).toBeGreaterThan(0)
    for (const file of existing) {
      const items = JSON.parse(readFileSync(file, "utf8")) as readonly { action: string }[]
      for (const item of items) {
        expect(rubricActions.has(item.action)).toBe(true)
      }
    }
  })
})

function range1to15(): readonly number[] {
  return Array.from({ length: 15 }, (_, i) => i + 1)
}
