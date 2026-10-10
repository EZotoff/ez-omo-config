import { expect, test } from "bun:test"
import { pickTarget } from "../src/targets"
import { projectTurns } from "../src/projector"
import type { Message } from "../src/types"

const registry = { humanMessageIDs: new Set<string>(), supervisorMessageIDs: new Set<string>() }
const messages: readonly Message[] = [
  { id: "u1", sessionID: "s", role: "user", time: { created: 1 }, parts: [{ id: "p1", messageID: "u1", type: "text", text: "[supervisor] continue" }] },
  { id: "a1", sessionID: "s", role: "assistant", time: { created: 2, completed: 3 }, parts: [{ id: "p2", messageID: "a1", type: "text", text: "Say A/B/C." }] },
]

test("flag-on machine-origin projection exposes reply and provenance", () => {
  const turns = projectTurns(messages, registry, { adjudicateMachineOrigin: true })
  expect(turns[0]?.transcript).toContain("[origin: supervisor]")
  expect(turns[0]?.transcript).toContain("Say A/B/C.")
  expect(pickTarget(turns, messages, { adjudicateMachineOrigin: true })).toMatchObject({ target: { assistantMessageID: "a1" } })
})

test("flag-off retains origin exclusion but reports its real reason", () => {
  expect(projectTurns(messages, registry)[0]?.transcript).toBe("")
  expect(pickTarget(projectTurns(messages, registry), messages)).toMatchObject({ rejected: "origin-excluded" })
})

test("all target rejection reasons are typed in flag-on mode", () => {
  const turns = projectTurns(messages, registry, { adjudicateMachineOrigin: true })
  const options = { adjudicateMachineOrigin: true }
  expect(pickTarget([], [], options)).toMatchObject({ rejected: "missing-context" })
  expect(pickTarget(turns, messages, { ...options, sessionProtected: true })).toMatchObject({ rejected: "protected" })
  expect(pickTarget(turns, [...messages, { id: "u2", sessionID: "s", role: "user", time: { created: 4 }, parts: [] }], options)).toMatchObject({ rejected: "stale-target" })
  const last = messages[1]
  const first = messages[0]
  if (last === undefined || first === undefined) throw new Error("fixture incomplete")
  expect(pickTarget(turns, [first, { ...last, finish: "aborted" }], options)).toMatchObject({ rejected: "aborted" })
})
