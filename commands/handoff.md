---
description: Emit a handoff artifact for this session (optionally specify a slug)
---

Emit a handoff artifact for the current session using the handoff-relay skill procedure (load it via the skill tool if available; otherwise apply the procedure below inline).

Emit at a stable boundary only. If the current moment is mid-task, say so and ask whether to checkpoint-and-emit anyway.

Write the artifact to `.builder-kit/audit/handoff-<slug>-<YYYY-MM-DD>.md` (slug defaults to a 2-4 word kebab-case summary of the session's mission) with sections: Mission / Entry artifacts (read these first) / State (done with commit refs, in flight with exact coordinates, gotchas) / Next steps (numbered, each with a verifiable done-condition) / Prohibitions. Header records: emitted timestamp, source session ID, source head (sha + branch + clean/dirty), and which previous handoff this supersedes.

Rules: cite commits and session IDs exactly; a dirty tree is a warning label in the header, not a blocker; if a previous handoff file exists for this thread, mark it superseded.

Reply with the artifact path and a 3-line summary. Do not continue working on anything else after emitting — the next move (usually `/resume-from` in a fresh session) belongs to the operator.
