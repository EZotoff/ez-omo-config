# OpenCode Project Supervisor

Phase 0 is a read-only external observer. It reconciles top-level project sessions over HTTP, listens to SSE as a wake-up hint, projects human-visible turns, runs shadow judgment ticks, and records decisions in a local hash-chained ledger. It never writes to an OpenCode session.

The bundled `supervisor.json` installs to `$HOME/.config/opencode-supervisor/supervisor.json`. The loader prefers that runtime path and otherwise uses the bundled file. Unknown keys and modes fail closed. Modes: `off` (root ignored), `shadow` (read-only: judge + log), `observe` (P1a: shadow plus ESCALATE — tickets are written to the per-root `[Supervisor]` console session only, never into worker sessions), `full` (all interventions; not enabled anywhere yet). CONTINUE/STEER/REFORMULATE writes remain locked regardless of mode until their gates are met. EXCEPTION (first live gate, 2026-09-21): a root may set `continue_writes: {enabled: true, daily_cap: 5, kick_start_only: true}` — CONTINUE decisions on that root are DELIVERED into the worker session as visible `[supervisor] (continue)` nudges, gated on: kick_start mode only, pre-write premise re-check (target reply still the session's last message), per-root daily cap, protection registry. Write-enabled roots (2026-10-01): ez-omo-bench, ez-omo-dash, ez-omo-config, ComfyUI. REFORMULATE writes (demand a standalone first-principles re-explanation) wired 2026-10-02 with the same config shape (`reformulate_writes: {enabled, daily_cap}`, default cap 3).

APPROVE writes (2026-10-03, operator decision Option C via console ruling): trivial in-scope "shall I?" moments (POLICY rule 256) are answered by the supervisor instead of the operator. Config `approve_writes: {enabled, daily_cap, mode}` where `mode: observe` counts and logs would-grants (`TICK_SKIPPED approve write: WOULD-GRANT (observe): …` + `status.json#approveWrites`) while granting NOTHING, and `mode: grant` delivers `"[supervisor] (approve) Go-ahead granted: …"` with a mandatory FYI toast + `INTERVENTION_SENT mode=approve`. Staged tightening (approve-v1, `effective_from: next-epoch`) lives at `configs/opencode-supervisor/policy-staging/approve-tightening-v1.md`; review log at `~/.local/state/opencode-rollout/supervisor-approve-writes.review.md`. Rollout: observe on the 4 steering roots, monitor ladder `rollout-supervisor-approve-writes` (systemd transient), unlock requires the monitor gate AND a human-review marker (`~/.local/state/opencode-rollout/supervisor-approve-writes.HUMAN-REVIEW-DONE`) after reviewing the would-grant ledger for false 'trivial in-scope' positives — per the console ruling that an agent must not expand its own authorization unreviewed. STEER writes use the same pattern (`steer_writes: {enabled, daily_cap}`, default cap 3) with an extra gate: STEER requires at least one citation outside the target session. Operator ticket answers are DELIVERED to the waiting worker session on write-enabled roots (`QUEUE_PROPAGATION_DELIVERED`); on non-write roots they stay recorded as `QUEUE_PROPAGATION_PROPOSED`.

| Field | Meaning |
|---|---|
| `server_url` | Existing OpenCode server URL |
| `server_url` | Existing OpenCode server URL |
| `server_username` / `server_password_env` | HTTP Basic auth; password read from this env var at runtime (default `OPENCODE_SERVER_PASSWORD`, supplied by the systemd unit's `EnvironmentFile`) |
| `initial_window_days` | First-scan horizon: only sessions updated within this window are supervised (default 7) |
| `fetch_concurrency` | Bounded parallel HTTP fetches during reconcile scans (default 8) |
| `model` | Provider and model ID used for stateless judgment ticks |
| `grace_period_s` | Delay after idle before a tick |
| `min_intervention_interval_s` | Minimum interval between ticks for a root |
| `max_tick_concurrency` | Global tick concurrency ceiling |
| `target_history_cap_pairs` | Target-session history pair cap |
| `sibling_turn_window` | Recent changed turns included per sibling |
| `token_budget` | Hard input cap (40000) — approximate tokens via characters ÷ 4 |
| `tier_budgets` | Per-tier context budgets (target_history 15000, hot 8000, warm 6000, cool 4000, cold 2000); overflow degrades COLD→COOL→WARM then trims L1 oldest — never ABSTAIN-by-truncation unless L0 alone overflows |
| `confidence_floor` | Decisions below this confidence become `ABSTAIN` |
| `roots[].mode` | `off`, `shadow`, `observe`, or `full` per root (all twenty project roots `observe` since 2026-10-01 fleet rollout) |
| `roots[].trust` | Per-root trust block: `autonomous_deploy`, `autonomous_credentialed_actions` (both false everywhere) |
| `roots[].autonomous_path_globs` / `autonomous_title_prefixes` | Autonomous-origin classification keys (origin via `origins.ts`; autonomous origins are exempt from some intervention gating) |
| `roots` | Project paths supervised by the service |

## v2 architecture (post supervisor-rollout)

- **Context assembler v2** (`src/assembler.ts`): L0 target verbatim + L1 history (≤50 pairs) + L2 siblings in recency tiers (HOT <2h, WARM <24h, COOL <7d, COLD title-only) with titles, + L3 self-memory; tiered degradation under the 40k budget.
- **Collect-vs-decide fork** (`src/collect.ts`): when a judgment names `information_need` (not self-reported confidence), one bounded extra gather round — ≤3 lookups, ≤30s, ≤8k tokens — then a final decide; ESCALATE with a named need must collect before ticketing; runaway guard caps the collect rate (20% target / 50% hard).
- **Session-health classifier** (`src/health.ts`): aborted / errored / stalled / healthy classification from the assistant run; aborted sessions are excluded as CONTINUE targets (abort guard).
- **AttentionQueue** (`src/queue.ts`, contract Seam 4): durable queue (`schemaVersion: 1`) with dedupe, lease, prioritization, revalidation; channels collect, ticks propose, only the queue surfaces.
- **Console channel** (`src/console.ts`): tickets surface through the per-root `[Supervisor]` console session (enqueue→revalidate→surface→correlate→resolve). Live cycle in progress.
- **Protection command**: `bun run supervisor/src/status-cli.ts protect <sessionID> [--reason]` / `unprotect` — persists to `~/.local/state/opencode-supervisor/protected.json`; protected sessions are skipped for CONTINUE-class targets (ESCALATE may still surface).

Runtime state is under `$HOME/.local/state/opencode-supervisor/`: `status.json`, `ledger.jsonl`, `protected.json`, `operator-view.json` (atomic read model for operator-facing consumers — see docs/portable-supervisor-contract.md), and `grading/` artifacts. The API key is read from `$HOME/.local/share/opencode/auth.json` and is never written to status, ledger, or logs.

Deployed via the `opencode-supervisor.service` systemd unit (observe mode). Evidence: `repo_implemented` + `tests_passed` (`supervisor/test/`, 21 suites); `runtime_loaded` for queue/status/protect CLI and the service; console-channel live cycle in progress. Not verified live: `real_project_behavior_proven`.

## Consumers

`voice-bridge` (Vox) reads the ledger read-side to surface escalations to the voice agent — it tails `ledger.jsonl` and triggers on `TICK_DECIDED` with `action=ESCALATE` and `confidence ≥ 0.7`. It never writes to the ledger or the supervisor. See `docs/voice-bridge.md` and the ownership split in `docs/portable-supervisor-contract.md` (Seam 4).

### Continuation alerts (journal→ledger bridge) — the contract Vox consumes for crash events

**Status: wired and verified live 2026-09-23 (Vox consumer not yet built — this section is the handoff contract).**

Producer chain: `scripts/restart-with-continuation.sh` (ExecStop/ExecStartPost hooks + checkpoint timer) emits journal alerts under tag `restart-continuation`, each carrying a machine-readable suffix `unit=<u> reason=<r> rc=<n|-> uuid=<uuid|-> count=<n|-> ts=<epoch>` with reasons `preflight_failed | snapshot_failed | resume_fallback | db_fallback`. `supervisor/src/journalbridge.ts` tails `journalctl --user -t restart-continuation` (persisted cursor + alert-fingerprint dedupe in `~/.local/state/opencode-supervisor/journal-bridge.json`), and imports each alert as exactly ONE `TICK_DECIDED` ledger entry:

```json
{"seq":11434,"type":"TICK_DECIDED","payload":{
  "decision":{"action":"ESCALATE","confidence":0.9,
    "rationale":"continuation alert: resume_fallback on opencode-bench.service (rc=-, count=1)"},
  "continuation":{"source":"continuation","unit":"opencode-bench.service",
    "reason":"resume_fallback","rc":"-","uuid":"<checkpoint-uuid>",
    "count":"1","ts":"<epoch>","fingerprint":"<sha256 of unit+reason+uuid+ts>"}}}
```

Vox semantics for these entries: `reason=preflight_failed` = a server wedged/crashed and no stop-snapshot could be taken; `reason=resume_fallback` = crash-class recovery ran and N sessions were re-prompted from checkpoint (recovery happened — informational unless count is large or repeated); `reason=snapshot_failed` = busy sessions existed but snapshot failed (sessions at risk); `reason=db_fallback` = last-resort resume without a checkpoint. Delivery latency: up to 10 min (bridge polls on the 600s `periodicReconcile`). The bridge is ESCALATE-ONLY: it never calls `promptAsync` or any session-writing API — the continuation scripts remain the single writer of recovery prompts (`.consumed-*` markers are one-shot). Dedupe guarantee: one journal alert → one ledger escalation across supervisor restarts; Vox should still dedupe on `fingerprint` defensively.

First organic catch: a real `:3030` degradation on 2026-09-23 (~12:22 local, `preflight_failed rc=28`) and a deliberate live drill the same day (SIGSTOP'd bench server → checkpoint → crash-resume → escalation, seq 11434).

## Action dispatch and evidence discipline (2026-10-02)

- Every action in the tick schema (`ACCEPT ABSTAIN CONTINUE STEER REFORMULATE ESCALATE`) is compile-time exhaustive in `supervisor/src/service.ts` (`assertDispatchHandlesEveryAction`) and structurally bijection-checked by `tests/test_supervisor_dispatch.sh`, which also runs the full `bun test` suite and `tsc --noEmit` inside `tests/run_all.sh`. A write-path action without a dispatch site fails the repo gate (schema-ghost prevention; STEER/REFORMULATE shipped as ghosts on 2026-09-22 and survived all reviews until 2026-10-02).
- Funnel invariant: every non-ACCEPT/ABSTAIN decision ends its tick with an effect or an explicit `TICK_SKIPPED`; otherwise an `ERROR` ledger event `action funnel violation` is appended and counted in `status.json#actionFunnel` (decided/effect/skipped per action).
- Doc claims in this README and MANIFEST.md must cite their evidence (dispatch site, test, or ledger event) — claims written by the implementing change without evidence are how the 2026-09-22 STEER mislabel survived 10 days.
