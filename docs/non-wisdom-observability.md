# Non-Wisdom Observability

This page links to per-system observability documentation for the four non-Wisdom systems in the OMO ecosystem. For Wisdom observability, see [docs/wisdom.md](wisdom.md).

## Systems

### Aspect Dynamics

- **Repo docs**: `configs/opencode/aspect-dynamics/` module docs, [configs/opencode/README.md](../configs/opencode/README.md)
- **Implementation**: `configs/opencode/aspect-dynamics.mjs`, `configs/opencode/aspect-dynamics/logging.mjs`
- **Tests**: `tests/test_aspect_dynamics_runtime.sh`
- **Performance review tooling**: `tests/perf-review/` benchmarks and `scripts/perf-review/` metrics/census scripts cover Aspect Dynamics, Output Shaper, Skill Nudger, provider-connect-retry, agent-default-guard, and live-config-guard.
- **Runbook section**: See `.sisyphus/evidence/task-11-non-wisdom-observability-runbook.md` — Aspect Dynamics

### Control Plane

- **External repo**: `/home/ezotoff/AI_projects/omo-control-plane`
- **Repo docs**: `docs/observability.md` (in the Control Plane repo)
- **Implementation**: `src/server/api.ts`
- **Tests**: `bun test` (156 tests)
- **Runbook section**: See `.sisyphus/evidence/task-11-non-wisdom-observability-runbook.md` — Control Plane

### Decision Extractor

- **External repo**: `/home/ezotoff/omo-hub/projects/decision-extractor`
- **Implementation**: `src/cli.ts`, `src/schema/run-summary.ts`
- **Tests**: `bun test` (239 tests)
- **Runbook section**: See `.sisyphus/evidence/task-11-non-wisdom-observability-runbook.md` — Decision Extractor

### DCP Bounded-Memory — RETIRED 2026-06-23

> DCP was removed and its config archived to `configs/opencode/dcp.jsonc.retired`; the DCP tests are `.retired` and the byte-budget reference moved to [docs/history/dcp-byte-budget.md](history/dcp-byte-budget.md). This section is kept as a pointer only.

- **Patch docs**: `.sisyphus/patches/opencode-dcp--bounded-range-archive-mode.md` (status: retired)
- **Historical reference**: `configs/opencode/dcp.jsonc.retired`, `tests/test_dcp_bounded_range.sh.retired`, `tests/test_dcp_startup_warning.sh.retired`

### Supervisor Ledger

- **`QUEUE_ITEM_SURFACED` bifurcation (analytics)**: rows written before the surfaced-truthfulness cutover (commit `83c0d4e`, 2026-10-10) meant **leased** — the item was handed to a presentation lease; rows from that cutover onward mean **confirmed delivery** — the item was accepted POST-surface (lease acquisition now emits `QUEUE_ITEM_LEASED` instead). The ledger type string is unchanged, so consumers MUST bifurcate by timestamp (against the cutover) or by accompanying fields — never pool the whole history under one semantic. Pooling inflates delivery counts and misreads lease churn as delivery.

### Continuation / Crash-Safe Recovery

The OpenCode serve daemons (interactive `:3030`, headless `:3021`, bench `:3040`) share a crash-safe continuation stack so busy sessions survive restarts and crashes.

- **Recovery classes** (priority order): stop-snapshot (systemd `ExecStop` hook) > 5-minute checkpoint (timer) > opt-in DB fallback (`CONTINUATION_DB_FALLBACK`, default OFF). Exactly-once: each snapshot/checkpoint/DB batch is consumed via a `.consumed-<unit>-<uuid>` marker, so a second `hook-resume` injects nothing (TTL 3600s).
- **Congested-stop hardening (2026-10-01)**: the stop-snapshot inventory runs with bounded parallelism (8 dirs at a time, `SNAPSHOT_CONCURRENCY`), a 45s budget (`SNAPSHOT_BUDGET_SECONDS`), and on budget overrun WRITES the partial inventory (snapshot file carries `"partial": true`) instead of discarding it — the 2026-09-30 congested restart lost 7 busy sessions because the old 15s sequential walk aborted before writing. `hook-resume` waits up to 60s (`RESUME_WAIT_SECONDS`) for readiness and retries each prompt POST every 2s up to 60s (`RESUME_RETRY_SECONDS`) instead of knocking once on a still-starting server. Contract test: `tests/test_continuation_hooks.sh`.
- **Wake-journal union + dedup (2026-10-14)**: `hook-resume` unions fresh non-terminal wake files (`<dir>/.omo/run-continuation/wakes/*.json`) into the resume batch. Freshness is judged by CONTENT age (`firstDispatchedAt`/`dispatchedAt`/`claimedAt`/`history[-1].at`, 6h cap) — never file mtime, which an unidentified writer mass-refreshed on 2026-10-13 (19 stale wakes touched in 4ms); timestamp-less wakes are skipped and multiple wakes for one session coalesce to the newest. The cross-run resume dedup window is 1800s (30 min). Backlog cleanup: `scripts/archive-stale-wakes.sh` (dry-run default; `--apply` moves non-terminal wakes with content age ≥ 6h into `archived-<stamp>/`, never deletes).
- **Wave A guards (2026-10-16, plan continuation-fp-wave-a.md; baseline 72% FP)**: (1) the wake union's `dispatched-awaiting-output` entries additionally require PARENT SILENCE — `session.time_updated < age_basis * 1000` (units: age_basis is seconds, time_updated ms; DB read is read-only and fail-open), since a dispatched notification whose parent already continued is the OMO consumption-detection leak, not a lost wake; (2) `resume()` applies the freshness guard (`time.updated > captured_at_ms` → `skip-stale`) to top-level snapshot entries, closing the finished-during-restart-gap false-positive class; (3) the dedup marker claim is atomic (`O_CREAT|O_EXCL`, stale reclaim re-checks mtime before unlink) across all three resume blocks — both servers restart simultaneously and share STATE_DIR (the old check-then-write produced up to 12 identical nudges/minute). Fixed 6h recycles are replaced by the quiesce-gate timer (`opencode-recycle-gate.{service,timer}`, OBSERVE=1 default: restart only at RSS ≥ threshold AND zero busy sessions; RuntimeMaxSec is a 24h backstop). Outcome accounting: `scripts/continuation-fp-report.py --days 7` (per-class FP/TP/precision from the session DB; the post-deploy measurement gate for this wave).
- **Checkpoint cadence**: `opencode-continuation-checkpoint.timer` runs every 5 minutes (`OnBootSec=2min`, `OnUnitActiveSec=5min`) and snapshots busy sessions for ALL THREE units — `opencode-interactive.service`, `opencode.service`, and `opencode-bench.service` (bench added 2026-09-23; per-unit failures are isolated via `-` prefixed `ExecStart` lines so one slow server cannot block the others' checkpoints); each write is atomic (`last-busy-<unit>.json`, fresh UUID), and a failed probe never clobbers the previous checkpoint.
- **Journal alert contract**: `scripts/restart-with-continuation.sh` emits `logger -t restart-continuation` alerts with a machine-readable suffix `unit=<u> reason=<r> rc=<n|-> uuid=<u|-> count=<n|-> ts=<epoch>`. Reasons: `preflight_failed`, `snapshot_failed`, `resume_fallback`, `db_fallback`.
- **Supervisor journal→ledger bridge**: `supervisor/src/journalbridge.ts` tails `journalctl --user -t restart-continuation` (persisted cursor + fingerprint dedupe) and imports each alert as ONE `TICK_DECIDED` escalation (`decision.action=ESCALATE`, `confidence=0.9`, continuation fields in the payload) — the shape Vox/Beacon consume. Escalate-only: it never calls `promptAsync` or any session-writing API. **Delivery latency up to 10 min** (bridge polls on the 600s `periodicReconcile`). Full Vox-facing payload contract, reason semantics, and a real ledger example: see "Continuation alerts" under Consumers in `configs/opencode-supervisor/README.md`. Verified live 2026-09-23 (organic `:3030` preflight_failed catch + deliberate bench crash drill, ledger seq 11434).
- **Bench instance**: `opencode-bench.service` is a dedicated headless server on `127.0.0.1:3040` (port from the deployment registry `~/.sisyphus/ports.json`, service key `opencode-serve-bench`). `scripts/bench-campaign` routes campaign sessions to it via `BENCH_SERVER_URL` (default `http://127.0.0.1:3040`) and `opencode run --attach`.

## Consolidated Runbook

The end-to-end observability runbook with commands, artifact paths, health checks, failure scenarios, retention policies, and test commands for all four systems is located at:

`.sisyphus/evidence/task-11-non-wisdom-observability-runbook.md`

## Test Evidence

Latest proof command outputs: `.sisyphus/evidence/task-11-final-commands.txt`

Performance-review evidence is generated by `tests/perf-review/` and `scripts/perf-review/`; both directories are repo-only tooling.

## Exclusion Rationale

Wisdom has its own dedicated observability system documented in [docs/wisdom.md](wisdom.md).
