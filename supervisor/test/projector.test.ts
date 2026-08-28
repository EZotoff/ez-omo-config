import { describe, expect, test } from "bun:test"
import { projectTurns } from "../src/projector"
import { deriveChildSessionIDs, topLevelSessions } from "../src/topology"
import { patternFixtures } from "../src/patterns"
import type { Message, Session } from "../src/types"
import type { Origin } from "../src/types"

const message = (id: string, role: "user" | "assistant", text: string, synthetic = false): Message => ({
  id,
  sessionID: "ses-root",
  role,
  time: { created: 1 },
  parts: [{ id: `${id}-part`, messageID: id, type: "text", text, synthetic }],
})

describe("projectTurns", () => {
  test("projects a plain human turn when the message is registered human", () => {
    const turns = projectTurns(
      [message("u1", "user", "Please inspect this"), message("a1", "assistant", "Done")],
      { humanMessageIDs: new Set(["u1"]), supervisorMessageIDs: new Set() },
    )
    expect(turns[0]).toMatchObject({ origin: "human", transcript: "USER: Please inspect this\nASSISTANT: Done" })
  })

  const cases: readonly (readonly [string, Message, Origin])[] = [
    ["synthetic", message("u1", "user", "hidden", true), "machine-synthetic"],
    ["ralph", message("u1", "user", patternFixtures.ralph), "machine-template"],
    ["retry", message("u1", "user", patternFixtures.retry), "machine-template"],
    ["aspect", message("u1", "user", patternFixtures.aspect), "machine-template"],
    ["supervisor registry", message("u1", "user", "registered"), "supervisor"],
    ["supervisor prefix", message("u2", "user", "[supervisor] observe"), "supervisor"],
    ["unknown", message("u3", "user", "odd unregistered input"), "unknown"],
  ]
  test.each(cases)("classifies %s in the required order", (_name, user, origin) => {
    const supervisorMessageIDs = new Set(user.id === "u1" && user.parts[0]?.text === "registered" ? ["u1"] : [])
    const turns = projectTurns([user], { humanMessageIDs: new Set(), supervisorMessageIDs })
    expect(turns[0]?.origin).toBe(origin)
  })

  test("includes unknown text with an origin label", () => {
    const turns = projectTurns([message("u1", "user", "unclassified")], {
      humanMessageIDs: new Set(),
      supervisorMessageIDs: new Set(),
    })
    expect(turns[0]?.transcript).toBe("USER [origin: unknown]: unclassified")
  })
})

test("topLevelSessions excludes child sessions by parentID and by task-part derivation", () => {
  const sessions: readonly Session[] = [
    { id: "ses_root", directory: "/project" },
    { id: "ses_child", directory: "/project", parentID: "ses_root" },
    { id: "ses_spawned", directory: "/project" },
  ]
  const childIDs = deriveChildSessionIDs([
    {
      id: "m1",
      sessionID: "ses_root",
      role: "user",
      time: { created: 1 },
      parts: [
        {
          id: "p1",
          messageID: "m1",
          type: "tool",
          tool: "task",
          state: { input: { sessionID: "ses_spawned" }, metadata: { sessionID: "ses_spawned" } },
        },
      ],
    },
  ])
  expect(topLevelSessions(sessions, childIDs).map((session) => session.id)).toEqual(["ses_root"])
})

test("deriveChildSessionIDs ignores non-task tools and non-session text", () => {
  const messages: readonly Message[] = [
    {
      id: "m2",
      sessionID: "ses_root",
      role: "assistant",
      time: { created: 2 },
      parts: [
        { id: "p2", messageID: "m2", type: "tool", tool: "bash", state: { input: { command: "echo ses_notachild" } } },
        { id: "p3", messageID: "m2", type: "text", text: "mentioned ses_in_text but not a task" },
      ],
    },
  ]
  expect(deriveChildSessionIDs(messages).size).toBe(0)
})
