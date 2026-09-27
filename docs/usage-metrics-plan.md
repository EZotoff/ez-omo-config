# Usage & Efficiency Metrics — Design Proposal

**Status:** Proposal (2026-09-27) · Episode: `.omo/episodes/usage-metrics-expansion/`
**Goal:** Collect durable usage/performance/efficiency stats across the OpenCode+OMO fleet: (A) agent efficiency — token/cost consumption per model/provider/agent type; (B) human efficiency — session idle time and human-response latency, correctly excluding machine-originated turns; plus forward-looking metrics for the attention queue and Vox.

## 1. What already exists (survey findings)

| Collector | What it records | Gap |
|---|---|---|
| **omo-pulse** (`~/AI_projects/ez-omo-dash`) | On-demand per-**model** token aggregation (input/output/reasoning/cache read/write) derived from the OpenCode SQLite DB; tool-call activity time series; current idle/running states | Recomputed on demand — no durable historical series; no per-provider or per-agent rollup; no cost; no human-response latency |
| **Supervisor ledger** (`~/.local/state/opencode-supervisor/ledger.jsonl`) | Hash-chained events: `TICK_DECIDED` (action, rationale, confidence), `WORKER_TURN_COMPLETED`, escalations, queue events; in-memory `METRICS_SNAPSHOT` (tick counts, queue depths, collect token *estimates* via chars/4) | No model/provider/tokens per turn; no measured elapsed times; collect tokens never persisted per tick |
| **Session-learning nightly sweep** | Behavioral mining of stale sessions (agent/model, message counts, tool/error/mutation counts, commits) | Learning-candidate oriented, not metering; no tokens/spend/duration |
| **Bench campaign runner** | Per-case `{phase, caseId, exitCode}` + full logs | No token counts, cost, or per-case duration in structured results |
| **Quota scripts** (`quotas.sh`, dash `/api/quotas`) | Provider quota windows/percent/reset for 5 providers, ~3-min cache | Percentages, not consumption; not persisted as history |
| **Session archives** (`opencode_maintenance.py`) | Lossless raw session/message/part rows, indefinite retention | Raw data only, no aggregates — but this is our backfill source |

**Bottom line:** raw per-message telemetry is already persisted by OpenCode itself; nothing builds durable, queryable efficiency aggregates from it, and nothing measures human responsiveness.

## 2. What the data layer gives us (schema facts)

Evidence: `~/src/opencode/packages/schema/src/session-message.ts`, `session.ts`, `session-event.ts`, `session-status-event.ts`; `packages/core/src/session/sql.ts`; local DB samples.

- **Per assistant message (persisted):** `cost`, `tokens {input, output, reasoning, cache.read, cache.write}`, `modelID`, `providerID`, `agent`, `finish`, `time.created/completed`. Per session: aggregate cost + token totals.
- **Live events (plugin-subscribable):** `Step.Ended` carries cost + token totals per step; `chat.message` gives session/message/agent/model context; `session.status` gives busy/idle/retry transitions. A server plugin in `opencode.json#plugin` can account usage in real time.
- **Turn-finish signal:** assistant `time.completed` (session `updated` is not a turn-finish timestamp). Response latency = next prompt's `time.created` − previous assistant `time.completed`.
- **⚠ Origin attribution is the hard gap:** message types distinguish `user` / `synthetic` / `system`, but genuine `user`-role records carry **no human-typed flag**. Every injector (continuation nudges, restart-with-continuation's `prompt_async`, supervisor prompts, boulder/todo loops) writes ordinary user messages. Retroactive separation is heuristic-only; **the collector must own origin tagging at each injection point going forward**.

## 3. Proposed architecture

A single **usage collector plugin** (new, registered in `opencode.json#plugin`) + a **nightly aggregator script** + optional **omo-pulse surfaces**. Ledger-first, like the supervisor: append-only JSONL at `~/.local/state/opencode-usage/usage.jsonl` (hash-chained, same envelope pattern as the supervisor ledger).

```
Step.Ended / chat.message / session.status events
        │  (usage collector plugin, per server instance)
        ▼
usage.jsonl  ──nightly aggregator──▶  rollups (sqlite or json) ──▶ omo-pulse
        ▲
origin tags injected at machine-prompt injection points
```

### Wave 1 — Agent efficiency (tokens per model/provider/agent)

1. **Usage collector plugin**: subscribe to `Step.Ended` + `chat.message`; append `{ts, sessionID, agent, providerID, modelID, tokens{...}, cost, stepDurationMs, variant}` to `usage.jsonl`. Dedup on messageID (Step.Ended and message persistence overlap).
2. **Backfill**: one-shot script derives historical per-model/provider/agent rollups from the session DB (proven feasible — omo-pulse already does this per-model; extend keys to provider + agent and persist).
3. **Aggregation**: nightly job produces daily rollups keyed by `date × provider × model × agent`: tokens in/out/reasoning/cache, cost, steps, sessions. Retention indefinite (tiny rows).
4. **Surface**: omo-pulse panel — tokens & cost by model/provider/agent over time; identify the expensive agents (oracle/metis on gpt-6-sol vs sisyphus on glm-5.3-flash, etc.).

Success criteria: rollup totals reconcile with session-level aggregate columns in the DB (± dedup tolerance); omo-pulse renders the panel from the rollup store.

### Wave 2 — Human efficiency (idle / human-response latency)

**Definition of a human turn** (collector-owned tagging, not heuristics):
- Genuine human = user-role message whose session had no active machine-injection path at prompt time.
- **Tagged as machine** (known injectors, tagged at source): restart-with-continuation.sh (ours — add an origin marker to its injected prompt metadata), OMO continuation/nudge hooks, boulder/todo continuation, supervisor `prompt_async` injections, `[SYSTEM REMINDER]`-bearing messages (heuristic fallback only).
- Everything untagged ⇒ `origin: unknown` — reported **separately**, never counted as human (honest denominator).

**Metrics**:
- Human response latency: assistant `time.completed` → next *human* message `time.created`; report p50/p90 + distribution, per project.
- Session idle time: `session.status → idle` until next human message or session close; bucket by <5m / <1h / <1d / abandoned.
- Nudge efficacy: after a machine continuation/nudge, did the human eventually reply, or was the session abandoned? (directly informs whether auto-nudges waste tokens).
- Human interruptions: human prompt arriving while busy (attention-queue leading indicator).

Success criteria: for a sample week, ≥95% of user-role messages classified as tagged-machine or unknown-or-human with no false "human" labels on known injections.

### Wave 3 — Forward-looking (attention queue + Vox + cross-cutting)

- **Attention queue**: time-in-queue and time-to-acknowledge for `TICK_DECIDED+ESCALATE` events (ledger already has the timestamps — add aggregation, not collection); escalation precision (human accepted vs overrode the escalate decision — needs Vox/reply-inbox outcomes joined by correlation ID).
- **Vox** (voice-bridge): voice-command success rate, confirmation-gate accept/reject ratio, interrupt latency, per-tool time-to-execute, mutations confirmed vs rejected. Collect inside voice-bridge, emit as ledger-style JSONL with the same envelope so the aggregator joins it.
- **Quota history**: nightly cron samples `quotas.sh --json` into a durable series → headroom forecasting (today's quota % is ephemeral).
- **Bench campaign enrichment**: extend `case-results.jsonl` with per-case duration + tokens (runner already owns the process lifetime).
- **Fallback-chain effectiveness**: count retries/fallbacks per provider from retry events (`session.status retry` + retry-plugin log) — quantifies which fallback chains actually fire.

## 4. Build order & sizing

| Order | Item | Size | Notes |
|---|---|---|---|
| 1 | Usage collector plugin (W1) | M | New plugin in this repo; register in `opencode.json#plugin`; restart-with-continuation applies |
| 2 | Backfill + nightly aggregator (W1) | M | Python, mirrors `opencode_maintenance.py` conventions; reads session DB |
| 3 | Origin tagging at injectors (W2) | S-M | restart-with-continuation first (ours); OMO hook paths need fork-patch or plugin-level tagging — investigate reachability |
| 4 | Latency/idle aggregation (W2) | S | Same aggregator |
| 5 | omo-pulse surfaces | M | Sibling repo; panels for W1+W2 |
| 6 | Quota sampler + bench enrichment (W3) | S | |
| 7 | Attention-queue/Vox metrics (W3) | M | Lands with those features; contract via `docs/portable-supervisor-contract.md` |

## 5. Constraints & risks

- **Origin honesty**: heuristic "looks human" classification is explicitly rejected; untagged ≠ human. Expect early weeks to have a large `unknown` share that shrinks as injectors get tagged.
- **Multi-instance**: both `opencode.service` (:3021) and `opencode-interactive.service` (:3030) run plugins — the collector must handle two writers to one JSONL (per-instance files, aggregator merges; avoids locking).
- **Cost accuracy**: OpenCode's `cost` field is model-catalog-derived; benchmark/whitelisted models may lack pricing — report cost as nullable.
- **Privacy**: all local-only, same posture as the supervisor ledger; no upload.
- **Version drift**: plugin subscribes to event schemas (`Step.Ended`, `session.status`) that may shift across OpenCode versions — schema-validated at aggregator ingest, same discipline as patch entries.
