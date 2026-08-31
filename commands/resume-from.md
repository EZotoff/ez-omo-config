---
description: Boot this session from a handoff artifact (slug, latest, or path)
---

Resume from a handoff artifact using the handoff-relay skill procedure (load it via the skill tool if available; otherwise apply the procedure below inline).

Argument: a slug, `latest`, or a file path. `latest` = newest `handoff-*.md` in `.builder-kit/audit/`.

Procedure, in order:
1. Read the artifact fully.
2. Validate before trusting: compare its recorded source head (sha/branch) against the repo's actual state. If HEAD has moved past it, list what changed since and mark affected next-steps STALE. If the tree it describes was dirty, say so.
3. Read the entry artifacts it cites; report any that are missing instead of improvising around them.
4. Present in ≤15 lines: mission → state (done / in flight / gotchas) → numbered next steps with STALE marks → prohibitions.
5. STOP at the decision checkpoint: continue / revise / archive. Do not begin any next step, spawn any agent, or edit any file before the operator answers.

If the artifact cannot be found, list available handoff artifacts and stop.
