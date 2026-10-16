# Plan: Task-list owned views (project-scoped store, session-default views)

Status: AUTHORED — awaiting operator `$start-work`. Design approved via supervisor
relay (ledger seq 121192, 2026-10-16). Origin: design discussion in
ez-omo-config session, 2026-10-16 ("session agents get confused by tasks from
other sessions").

## Problem (evidence)

The OMO `task_*` tools store tasks per project directory
(`~/.config/opencode/tasks/<listId>/T-*.json`; listId defaults to
`basename(session directory)` — `packages/omo-opencode/src/features/claude-tasks/storage.ts`,
`resolveTaskListId`). The store scoping is correct (2026-10-10 lock-contention
fix); the confusion is in the read surfaces:

1. `task_list` returns ALL active tasks in the project with summary fields
   `id/subject/status/owner/blockedBy` only — `threadID` is recorded at create
   (`task-create.ts:91`) but never shown; `owner` is only set if the calling
   agent passes it explicitly. A session cannot distinguish its own work from
   other sessions' stale work.
2. `task_list` output ends with the reminder *"Maximize parallel execution by
   running independent tasks (tasks with empty blockedBy) concurrently"* —
   written for an orchestrator viewing its own plan, but shown to every session
   viewing the shared board, actively inviting task-grabbing of foreign tasks.
3. No lifecycle: sessions die without closing tasks; nothing marks orphans, so
   every future session inherits them as noise.

## Coordination — Q27 / continuation-fp-wave-a (operator condition 2)

Cross-reference settled BOTH ways:

- **Wave A** (`.omo/plans/continuation-fp-wave-a.md`) owns the continuation
  **wake-nudge decider**: `scripts/restart-with-continuation.sh` union_wakes
  predicate, wake-journal hygiene, measured by `scripts/continuation-fp-report.py`
  from the session DB (FP = prior assistant message has `time.completed`). It
  does NOT ingest task-tool output and touches no OMO-fork files.
- **This plan** owns the **task-tool side**: the `task_list` concurrency nudge
  and task-tool output shaping. The two plans share only measurement vocabulary.
- Joint measurement point: wave A's post-deploy residual-class table. If
  residuals implicate a task-tool/reminder class, this plan's nudge removal is
  the task-side complement; neither plan edits the other's files.
- Wave A's doc gains a one-line reciprocal cross-reference (added with this
  plan's commit).

## Verification contract (pinned BEFORE code — operator condition 1)

All three must hold for Phase 1 acceptance:

- **VC-a (adjacent regression):** a session's own create → list → update →
  complete flow behaves identically to pre-fix: same status transitions, same
  blockedBy unresolved-filtering, same todo-sync. New summary fields are
  additive only. Proof: existing `task-*.test.ts` suite green plus a new
  within-scope regression test asserting field-level output compat.
- **VC-b (conflation RED→GREEN):** a test reproducing the actual confusion —
  two sessions sharing one taskDir; session A creates a task; session B's
  default `task_list` view. Pre-fix this test FAILS (B sees A's task as its
  own actionable work); post-fix it PASSES (B's default view excludes it;
  `scope=all` shows it with provenance). Written first, observed red, then green.
- **VC-c (live surface):** nudge removal and scope behavior observed on a real
  running session (real `task_list` calls via a live opencode session in a
  scratch project), captured as transcript/output evidence in the patch entry's
  Runtime Verification section. Not inferred from code, not satisfied by grep.

## Roadmap

- **Phase 1 — ownership in every read surface** (detailed below; execution-ready).
- **Phase 2 — orphan lifecycle.** GATED on Phase 1's measured outcome: proceed
  only if, after Phase 1 deploy, observation over ≥2 weeks of real sessions
  still shows foreign/orphan task confusion (operator judges via supervisor
  relay). Scope: tasks whose `threadID` maps to a dead session (session-store
  liveness check) and untouched for ≥14d get flagged `orphaned` (metadata flag),
  excluded from default views, listed in `scope=all` as reclamation candidates.
- **Phase 3 — soft mutation guard.** GATED on Phase 2 (or on a live incident
  showing agents still stomping live-owner tasks). Scope: `task_update` by a
  non-owner on a task whose owner session is still alive returns a provenance
  warning requiring explicit re-confirm; dead-owner tasks freely claimable.

## Phase 1 — detailed tasks

Source: OMO fork (`~/oh-my-openagent`, remote `fork` = EZotoff/oh-my-openagent).
Branch off the release tag matching the live installed runtime (resolve at
start-work: version in `configs/oh-my-openagent/oh-my-openagent.json` vs
`~/.opencode` install; currently v4.19.2 per AGENTS.md — verify, don't assume).

### T1 — schema: timestamps + list scope input
- `packages/omo-opencode/src/tools/task/types.ts`:
  - `TaskObjectSchema`: add `createdAt: z.string().optional()` and
    `updatedAt: z.string().optional()` (ISO-8601). `.strict()` + optional keeps
    existing on-disk task files parsing unchanged (VC-a).
  - `TaskListInputSchema`: add `scope: z.enum(["mine", "all"]).optional()`
    (default `"mine"` applied in the tool, not the schema, so old callers are
    unaffected).
- `task-create.ts`: stamp `createdAt`/`updatedAt` = now on create.
- `task-update.ts`: refresh `updatedAt` on any non-noop write.
- Tests: schema round-trip with and without timestamps (old files parse).

### T2 — task_list: default scope=mine, provenance in scope=all
- `packages/omo-opencode/src/tools/task/task-list.ts`:
  - Ownership key is **threadID** (authoritative): task is "mine" iff
    `task.threadID === context.sessionID`. `owner` match against the session's
    resolved agent name is a secondary match (best-effort; see T3). Legacy
    tasks missing threadID (none should exist — schema requires it — but guard
    anyway) count as unowned → visible in `mine`.
  - `scope=mine` (default): my tasks + unowned tasks + **external-dependency
    join**: active foreign tasks that block any of my tasks appear as
    dependency rows (marked `externalDependency: true`) — the one cross-view
    join that prevents real blindness.
  - `scope=all`: full board; each row gains `owner`, `threadID` (short form,
    first 8 chars), `ageDays`, `updatedAt`. Concurrency nudge
    ("Maximize parallel execution…") moves here — it is TRUE for an
    orchestrator viewing the board and removed from the default view
    (satisfies VC-c's target).
  - `task_get` remains ID-based and unfiltered (delegated children receive
    task IDs in prompts and must always resolve them).
- Description text of `task_list` updated to document `scope` and the
  mine-default so agents know `scope=all` exists.
- Tests (in `task-list` test file, mirroring existing task-*.test.ts style):
  - VC-b conflation test (two sessions, one taskDir) — written FIRST, red
    before T2 lands, green after.
  - external-dependency join test.
  - scope=all provenance fields test.
  - unowned/legacy task visibility in `mine`.

### T3 — task_create: auto-ownership sugar
- `task-create.ts`: `threadID` is already stamped (line 91) — no change needed
  for correctness. Add best-effort `owner` stamping: resolve the current OMO
  agent name for the session (implementation item: find the existing agent
  registry/lookup used elsewhere in the plugin; if no reliable source exists,
  OMIT owner rather than inventing a name — threadID remains the ownership
  key). Decision rule recorded here so implementation doesn't freelance.

### T4 — adjacent-surface regression proof (VC-a)
- New test: own-task lifecycle (create → list(mine) → update → complete →
  list) asserting every pre-fix field keeps its value and transitions; run
  full `task-*.test.ts`; also run the claude-tasks storage tests.

### T5 — deploy + live verification (VC-c)
- Build/install through the EXISTING update-to-latest queue discipline — not
  ad hoc (OMO runtime is loaded via `opencode.json#plugin` `file://` entry;
  restarts go through `scripts/restart-with-continuation.sh` hooks).
- Live observation: scratch-project session exercises `task_list` (default and
  `scope=all`) and confirms: no concurrency nudge in default view; foreign
  task hidden; provenance visible in `scope=all`. Capture output as evidence.
- Patch entry `.sisyphus/patches/oh-my-openagent--task-list-owned-views.md`
  (follow TEMPLATE.md schema; this is plugin tool-layer code, not a rendering
  path — no `surfaces` required, but include a Runtime Verification section).
- Push the fork branch to the `fork` remote BEFORE `status: active`
  (AGENTS.md patch-preservation rule 8). `runtime_effective: true` only after
  T5's live observation.

## Success criteria / stop conditions

- VC-a, VC-b, VC-c all green with evidence.
- `bash tests/run_all.sh` passes in ez-omo-config (no repo-gate regressions
  from the patch entry).
- Docs updated per Documentation Sync Requirements: MANIFEST.md Patch Registry
  row, docs/patches.md if the entry introduces a new pattern, and the
  reciprocal cross-reference line in continuation-fp-wave-a.md.
- Phase 2/3 remain gated — this plan does NOT implement them.

## Non-goals

- No storage scoping change (per-project store stays).
- No hard mutation permissions (Phase 3 is soft and gated).
- No change to `team_task_*` (already team-run-scoped) or to subagent
  delegation task plumbing.

## Execution Record

(append `Execution baseline:` SHA at start-work; F#n verdicts during final wave)
