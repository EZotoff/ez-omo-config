import type { Message, Session } from "./types"

const SESSION_ID = /ses_[A-Za-z0-9]+/g

/**
 * Derives child (subagent) session IDs from task-tool parts in parents' messages.
 * The session API does not expose parent_id, but every task tool part embeds the
 * child session ID in its state (input/metadata). Sessions never referenced as a
 * child are top-level. Verified against live opencode 1.18.5 on 2026-08-28.
 */
export function deriveChildSessionIDs(messages: readonly Message[]): ReadonlySet<string> {
  const children = new Set<string>()
  for (const message of messages) {
    for (const part of message.parts) {
      if (part.type !== "tool" || part.tool !== "task") continue
      const blob = JSON.stringify(part.state ?? {})
      for (const match of blob.matchAll(SESSION_ID)) children.add(match[0])
    }
  }
  return children
}

export function topLevelSessions(sessions: readonly Session[], childSessionIDs: ReadonlySet<string>): readonly Session[] {
  return sessions.filter((session) => session.parentID === undefined && !childSessionIDs.has(session.id))
}

export type RootTopology = {
  readonly root: string
  readonly sessions: readonly Session[]
  readonly supervised: boolean
}

export function classifyRoot(root: string, sessions: readonly Session[], childSessionIDs: ReadonlySet<string>, mode: "shadow" | "off"): RootTopology {
  return { root, sessions: topLevelSessions(sessions, childSessionIDs), supervised: mode === "shadow" }
}
