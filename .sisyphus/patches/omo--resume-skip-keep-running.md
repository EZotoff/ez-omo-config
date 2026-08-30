---
patch_id: "omo--resume-skip-keep-running"
dependency: "oh-my-openagent"
target_file: "packages/omo-opencode/src/features/background-agent/manager.ts"
target_install_path: "/home/ezotoff/oh-my-openagent-v4.19.2"
source_repo: "/home/ezotoff/oh-my-openagent-v4.19.2"
status: "active"
applied_date: "2026-08-30"
dep_version: "4.19.2"
runtime_effective: false
upstream_issue: "none"
verification_pattern: "keeping task running until next idle"
note: "Source patch on branch fix/custom-patches-v4.19.2, commit 8b883adab ('patch: resume-skip-keep-running v4.19.2'). Upstream unfixed as of v4.19.4 and v5.0.0-beta.30 (restore fn byte-identical) — patch remains necessary across upgrades until upstream adopts. Pre-fix dist bundle preserved at dist/index.js.pre-resume-skip-keep-running for kill-test 017."
---

# Resume-Skip Keep-Running (background-task continuation deadlock)

## Problem

Dispatching a continuation via `task(task_id=...)` to a background task whose session is
transiently **busy** deadlocks the parent silently (observed 2026-08-30 17:12–17:22 UTC,
`ses_facae8e4affezS7URnSTmMXIbz` / task `bg_c16e323d`):

1. Round 1 completes normally (session.idle → `notifyParentSession` → parent notified).
2. The parent resumes the completed task with a continuation prompt. At resume time the
   child session is momentarily active (e.g. a nested-task notification wake in flight),
   so the prompt-async-gate returns status `"active"` — the resume prompt is **dropped**
   (not deferred; only `"queued"` defers).
3. `restoreTaskAfterSkippedResume` rolls the task back to its pre-resume snapshot status
   (`completed`), releases the concurrency slot, and schedules the 10-min cleanup timer.
4. The continuation work may still run (the dropped prompt can be redelivered by other
   paths), but when the session finally goes idle, `handleSessionIdleBackgroundEvent`
   bails at `task.status !== "running"` → **no completion, no parent notification**.
5. The cleanup sweeper then removes the task from memory ("Removed completed task").
   The parent — which ended its turn "waiting for the completion notification" — waits
   forever. No error, no abort, no user-visible failure.

## Patch Description

In `restoreTaskAfterSkippedResume` (packages/omo-opencode/src/features/background-agent/manager.ts),
added an early-return branch for gate statuses `"active"` and `"reserved"`:

- The task **stays `running`** with the full state `resume()` already established before
  dispatch (concurrency slot held, fresh `startedAt`, `pendingByParent` entry, toast).
- All rollback side effects are skipped: no `cleanupPendingByParent`, no concurrency
  release, no snapshot field restore, no toast removal, no `scheduleTaskRemoval`.
- Rationale: a session that is busy is guaranteed to emit `session.idle` when the
  in-flight turn ends; with the task still `running`, that idle completes the task and
  notifies the parent. Worst case (prompt truly lost AND no further idle) is bounded by
  the task-poller stale timeout (45 min → interrupt + notify) — never a permanent
  deadlock.
- Gate status `"unavailable"` keeps the legacy rollback (rare: broken client, no
  dispatch function).

Behavioral tests flipped from pinning the bug to pinning the fix:
`manager.test.ts` "keeps task running when resume prompt is skipped because the session
is active" and "...skipped by an existing reservation" (status stays `running`,
`completedAt` undefined, concurrency slot held, pendingByParent entry present under the
new parent, no completion timer scheduled).

## Verification

Pattern (necessary, NOT sufficient):

```bash
grep -c 'keeping task running until next idle' ~/oh-my-openagent-v4.19.2/packages/omo-opencode/src/features/background-agent/manager.ts
grep -c 'keeping task running until next idle' ~/oh-my-openagent-v4.19.2/dist/index.js
```

Both must return ≥ 1 (source marker + compiled runtime bundle). Focused behavioral check:

```bash
cd ~/oh-my-openagent-v4.19.2/packages/omo-opencode && bun test src/features/background-agent/manager.test.ts -t "resume promptAsync gate state"
# expect: 2 pass, 0 fail
```

Regression pair: `tests/regressions/017-resume-skip-keep-running.sh` (+ `.kill.sh`).

## Runtime Verification

Required while `runtime_effective: false`. Surface-exercise steps:

1. Ensure the opencode server was started after the rebuilt dist (restart
   `opencode.service`; check server start time).
2. In any session, dispatch a background task that completes, then immediately dispatch
   a continuation via `task(task_id=...)` while the child session is busy (a nested
   notification wake or in-flight turn reproduces the "active" gate status).
3. Observe `~/.local/share/opencode/logs/oh-my-opencode.log`:
   - `[background-agent] resume skipped while session busy; keeping task running until next idle:` appears,
   - the task later reaches `Task completed via session.idle event` and the parent
     receives the `[BACKGROUND TASK COMPLETED]` reminder (the pre-patch run showed the
     literal-free log ending in `Removed completed task from memory` with no wake).
4. Flip `runtime_effective: true` only after step 3 is observed on the real surface.
