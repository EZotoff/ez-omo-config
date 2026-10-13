# Restart Lost Parented Subagent Children (2026-10-12 incident)

**Date**: 2026-10-13 (fix); incident 2026-10-12 06:23 UTC
**Plan**: [`.omo/plans/restart-continuation-subagent-coverage.md`](../../.omo/plans/restart-continuation-subagent-coverage.md) (main repo checkout)
**Evidence ceiling**: `repo_implemented` + `tests_passed` — live verification (a real service restart with a live background child) is operator-gated and pending.

## What happened

At 2026-10-12 06:23 UTC, `opencode-interactive.service` was restarted. The restart-continuation machinery resumed top-level sessions correctly (the consumed snapshot `consumed-snapshot-opencode-interactive.service-20261012-082259.json` shows the top-level resume firing), but **six parented subagent sessions were killed and nothing was captured or resumed for them** — their in-flight work was silently lost. Server log evidence: `~/.local/share/opencode/log/opencode.log` lines ~4452483–4452494.

## Why (four defects, D1–D4)

1. **D1 — capture-layer exclusion (3 sites).** All three capture layers (stop snapshot, periodic checkpoint, DB fallback) explicitly dropped sessions with a `parentID`: the snapshot/checkpoint paths skipped `parentID` entries outright, and the DB fallback's SQL filtered `parent_id is null`. Parented children never entered any resume inventory.
2. **D2 — wake union wired only into the script path.** `union_wakes` + `WAKE_PROMPT` ran only from `converge_snapshot` in the standalone `--restart` flow. The systemd drop-ins call `hook-snapshot`/`hook-resume` directly, so a plain `systemctl restart` — the common case — never unioned wake-journal entries.
3. **D3 — process-local task registry.** The parent's background-task registry dies with the server process. Even for a captured child, the normal wake/registry channel cannot re-kick it; `background_output(task_id=...)` lookups are dead after a restart. Direct `POST /session/:id/prompt_async` is the only working child-resume channel.
4. **D4 — empty wake journal for killed children.** Wake files exist only for owed notifications (completed/retrying background tasks). A child killed mid-flight never journals one, so the wake union could not cover them even where it ran (see D2).

## What the plan fixed (T1–T4, branch commits c9472d3 → 3888a64)

- **T1 — capture (c9472d3, bddb5db).** All three capture layers now emit a top-level `children[]` array alongside `sessions[]` (always present, even empty). Child entry shape everywhere: `{id, title, directory, status, time_updated, parentID: true, parentSessionID}`.
- **T2 — resume (42bae1b, bdd65f1).** `resume()` (snapshot path, script path, `--resume-only`) and the checkpoint + DB-fallback fallbacks iterate `children[]` and POST each child directly via `prompt_async` with a child-specific prompt (registry-dead notice + "emit result as final message text"), sharing the same budget/dedup/freshness machinery as top-level entries.
- **T3 — hook-path wake union (da3849a).** `union_wakes` moved above the hook block and now runs at all three hook-resume sources (snapshot/checkpoint/DB fallback), unioning fresh non-terminal wake-journal parents in-memory (mktemp copy — the hook never mints extra snapshot files) so owed-notification parents receive `WAKE_PROMPT` on a plain service restart. Honest limit (D4): this covers only owed-notification wake files; killed children ride the T1/T2 `children[]` capture+resume instead. Full coverage of dispatch-time wakes needs OMO-side wake journaling (out of scope, OMO fork).
- **T4 — tests (61e0ee6, 3888a64).** Regression pair `tests/regressions/035-restart-loses-parented-children.{sh,kill.sh}` (kill test runs the pre-T1 script from git `e9554f8` and proves the child was dropped); `tests/test_continuation_hooks.sh` extended 8→14 passes (children capture semantics, child resume with freshness/dedup guards, hook-path wake union); `tests/test_resume_dispatch_timeout.sh` static contract extended to the new children dispatch sites.

## Verification state

- `tests/test_continuation_hooks.sh`: 14 passed | 0 failed. `tests/run_regressions.sh`: 43 passed | 0 failed (51 kill-tests proved).
- Functional probes under a stub server (sandbox HOME + synthetic session DB) proved: child POSTed with the child prompt; stale child skipped; second pass deduped; wake parent received `WAKE_PROMPT` with no extra snapshot file minted.
- **Not verified live**: a real service restart with a live background child (real_project_behavior_proven pending, operator-gated). The script changes are repo-side only; no systemd unit or live config changed in this plan.
