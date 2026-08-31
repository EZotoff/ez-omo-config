---
name: handoff-relay
description: Emit and resume cross-session handoff artifacts. Emit captures a session's mission, state, and next steps into a versioned file at explicit checkpoints; resume boots a new session from the artifact behind a continue/revise/archive decision checkpoint. Use for context handoffs between sessions, operators, or their agents.
---

# Handoff Relay — emit and resume

<role>
You operate a session-handoff relay. Emission packages THIS session's working state into a durable artifact at a stable boundary. Resume unpacks an artifact into a NEW session without blindly continuing. The operator decides at every boundary; you never continue work on the artifact's authority.
</role>

Triggers: `/handoff`, `/handoff emit`, `/resume-from`, "handoff", "new session", "hand this off"

## The acceptance boundary (non-negotiable)

- **Emit only at stable boundaries**: an explicit operator request, a completed work unit, or session close. NEVER emit merely because the context window is filling — a context-pressure snapshot captures an unstable moment and goes stale immediately.
- **Resume never auto-continues.** The first thing a resuming session does is present the decision checkpoint: **continue / revise / archive**. Execution begins only after the operator picks.
- The artifact is evidence, not authority.

## Emit procedure (`/handoff [emit] [slug]`)

Write `.builder-kit/audit/handoff-<slug>-<YYYY-MM-DD>.md` (create dirs as needed) with exactly these sections:

```markdown
# Handoff: <one-line mission>
- emitted: <ISO date-time> | source session: <id> | source head: <commit sha + branch + clean/dirty>
- supersedes: <previous handoff file or "none">   ← update the superseded file's status line if it exists

## Mission
What this thread is for and its current done-condition. 3–6 lines.

## Entry artifacts (read these first)
Numbered files/sections in reading order, each with a one-line "what you'll learn".

## State
- Done (with commit refs)
- In flight (exact coordinates: repo, branch, session IDs)
- Known gotchas / landmines

## Next steps
Numbered, each with a verifiable done-condition.

## Prohibitions
What the receiving session must NOT do (scope locks, "do not touch X").
```

Rules: cite commits and session IDs, never paraphrase them. If the tree is dirty, say so — a dirty-tree handoff is a warning label, not a blocker. After writing, reply with the file path and nothing else.

## Resume procedure (`/resume-from <slug|latest|path>`)

1. Resolve the artifact (latest = newest `handoff-*.md` by date in `.builder-kit/audit/`).
2. **Validate before trusting**: check `source head` against the repo — if HEAD has moved past it, list what changed since and mark affected next-steps **STALE**.
3. Read the entry artifacts it cites; confirm they exist. Missing artifacts = missing context; report, don't improvise.
4. Present, in ≤15 lines: mission → state summary → next steps (with STALE marks) → prohibitions.
5. **Decision checkpoint: continue / revise / archive.** Do not start any step until the operator answers.

## Cross-operator variant

If the handoff targets another operator's agent (different machine/tooling), add: environment requirements, deployment coverage, where each referenced file lives, and an onboarding paragraph assuming zero session history. Remove internal references the recipient cannot resolve.
