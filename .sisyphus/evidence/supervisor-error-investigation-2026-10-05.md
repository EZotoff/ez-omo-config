# Supervisor error-storm auto-investigation — 2026-10-05

Operator request (session in `ez-omo-config`): "Investigate what is causing [the errors] now. I'd also rather have this question get automatically created in an opencode session when the peak rises above a threshold (set 10 for now)."

## Part 1 — investigation: what is causing the error peak (165)

- All recent supervisor ERROR records (last 500+) share one signature: `opencode client failed: /session/ses_f6b1a0e31ffe3RXAmGU0npuL2Z/message?directory=…/ANIA&limit=50`, root `/home/ezotoff/AI_projects/ANIA`, ~150/hour (2–3/min).
- Live probe (curl, 2026-10-05 ~07:55 CEST): `HTTP 404 {"name":"NotFoundError","data":{"message":"Session not found: ses_f6b1a0e31ffe3RXAmGU0npuL2Z"}}` on both `/session/:id/message` and `/session/:id`.
- The session is in NEITHER `opencode.db` (python read-only query: row absent) NOR the live `/session` list for ANIA. It persists in `~/.local/state/opencode-supervisor/consoles.json` (`consoles["…/ANIA"]` + its watermark).
- Timeline: session created 2026-09-12 (`CONSOLE_INITIALIZED` seq 825); `db-fix-20261002.sh` bounced both opencode servers 2026-10-02 21:33–21:34 UTC (`db-fix-20261002-233353.log`); first 404 for this session 2026-10-02T23:58:12Z (ledger seq 13347); errors in waves ever since (peak 165 in hour 2026-10-05T03 UTC), surviving three supervisor restarts because `consoles.json` keeps the stale ID and `ConsoleChannel.ensure()` early-returns on existing entries.
- Secondary, distinct event: the 2026-10-03T07 UTC burst (2442 errors) was `/session?scope=project` LIST failures across ALL roots — the server being down during the bench-trim maintenance window (`bench-trim-20261003.sh`, 09:20 CEST). Transient, already past.
- Root cause (storm): **no stale-session eviction in the console poll path** — a 404 "Session not found" is recorded as ERROR telemetry every reconcile, forever. NOT fixed in this change (separate work item; the auto-investigation feature will now open a session about it each hour while it persists).

## Part 2 — feature: auto-created investigation session at peak threshold

- Config (store = live, symlinked): `configs/opencode-supervisor/supervisor.json` → `error_investigation: {enabled: true, threshold: 10}`; schema `supervisor/src/config.ts` (global, defaults `false`/`10`, strict).
- Dispatch: `maybeDispatchErrorInvestigation` (`supervisor/src/investigation.ts`), called from `recordErrorTelemetry` in `supervisor/src/service.ts` when `count >= threshold` — creates `[Supervisor] error investigation (<project>)` via `client.createSession` in the erroring root (fallback: supervisor repo) and prompts the classification question (ledger jq + journald sources inlined).
- Guards: once per 1-hour window; slot consumed BEFORE any await (no double-fire on slow dispatch) and even on failure (no session-creation loops); dispatch failure logs an `ERROR` ledger record that is deliberately NOT fed back through `recordErrorTelemetry` (no telemetry feedback loop).
- Observability: ledger `INTERVENTION_SENT` with `mode: "investigation"` (root, sessionID, count, peak, threshold); `status.json#errorInvestigations` counter; TUI toast with the session ID.

## Verification (evidence states)

- `repo_implemented`: commit containing supervisor/src/investigation.ts + wiring (landed inside `2e077fe` — a concurrent agent's commit swept up this session's uncommitted work; see coordination note).
- `tests_passed`: `bun test` 328 pass / 0 fail across 27 files; `tsc --noEmit` clean (both on combined HEAD after `2e077fe`); boot-path config parse verified via real `loadConfig`.
- Not verified live at write time: `runtime_loaded`, `real_project_behavior_proven` — pending supervisor restart + first organic dispatch (storm should cross threshold ~4–5 min after restart at current ~2.4 errors/min).

## Rollback

Flip `error_investigation.enabled` to `false` in `configs/opencode-supervisor/supervisor.json` and restart `opencode-supervisor.service`. Absent field = disabled (schema default).

## Coordination note

A concurrent agent session was committing an approve-writes epoch rework in this repo during this change (`1c9e4a0` stage, `2e077fe` apply). That commit included this feature's files. The flaky `policy.test.ts` failures observed mid-session were that agent's in-flight WIP, resolved in their final commit; full suite is green on `2e077fe`.

## Rollout

Monitor ladder `rollout-supervisor-error-investigation` (systemd transient unit `rollout-supervisor-error-investigation.service`, config `~/.local/state/opencode-rollout/supervisor-error-investigation.rollout.json`) — observation + evidence rounds, no unlock gates (single global flag, operator-authorized in-session).
