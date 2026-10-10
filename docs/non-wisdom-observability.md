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
