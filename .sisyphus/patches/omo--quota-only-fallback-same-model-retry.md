---
patch_id: "omo--quota-only-fallback-same-model-retry"
dependency: "oh-my-openagent"
target_file: "packages/omo-opencode/src/hooks/runtime-fallback/same-model-retry.ts, packages/omo-opencode/src/hooks/runtime-fallback/event-handler.ts, packages/omo-opencode/src/hooks/runtime-fallback/message-update-handler.ts, packages/omo-opencode/src/hooks/runtime-fallback/auto-retry.ts, packages/omo-opencode/src/hooks/runtime-fallback/auto-retry-cleanup.ts, packages/omo-opencode/src/hooks/runtime-fallback/hook.ts, packages/omo-opencode/src/hooks/runtime-fallback/types.ts"
target_install_path: "/home/ezotoff/oh-my-openagent-v4.19.2"
status: "active"
applied_date: "2026-09-14"
dep_version: "4.19.2"
runtime_effective: false
upstream_issue: "none"
verification_pattern: "SameModelRetry"
surfaces: [server-api]
note: "Source patch — carried by fork commit 3d507e2de on branch fix/custom-patches-v4.19.2 (restored 2026-09-18 from the implementation session transcript; the original implementation commits were destroyed with the runtime directory and never pushed — see Reapply Instructions). All listed target_file paths contain the SameModelRetry marker; session-status-handler.ts is ALSO changed (quota gate after the retry-key dedupe) but does not carry the marker, so it is documented here rather than in target_file. A 2026-09-14 `bun run build` embedded the patch in dist/index.js alongside the re-applied dist-level patches. runtime_effective is false until a real non-quota rate-limit event is observed staying on the current model (see Runtime Verification)."
---

# Quota-only model fallback + same-model exponential retry

## Problem

Z.AI's coding plan throttles *concurrent* requests. When the limit is hit the provider returns `Rate limit reached for requests` — a transient concurrency throttle, NOT quota exhaustion. OpenCode's native provider retry re-fired in ~2–4 s, its signals exceeded `retries_before_fallback`, and OMO's runtime-fallback hook aborted the request and switched models:
`zai-coding-plan/glm-5.3-flash → openai/gpt-5.6-sol`. Sol's own usage limit was exhausted, so the cascade walked on to `ollama-cloud/deepseek-v4.1-flash`. Observed live 2026-09-14 07:44:55–07:45:28Z (session `ses_f6324747dffegogA2yegTFrx9u`) and repeatedly on 2026-09-13 22:15–22:38Z (e.g. `ses_f63377bbeffeUe9g0SxOmUZB3x` firing 18 Z.AI stream attempts in 4 minutes).

The operator requirement: **fallback may happen ONLY on quota exhaustion.** Concurrency/rate-limit failures must keep retrying the SAME model with exponential backoff capped at two minutes.

## Patch Description

Source patch in the fork (8 runtime-fallback files, 5 commits):

1. **`same-model-retry.ts` (new)** — `createSameModelRetryHelpers(attempts, timeouts, dispatch)` owns timing only. Delay is `min(1000 * 2**attempt, 120_000)` ms, retried indefinitely; a pending timer per session suppresses duplicate scheduling; a rejected dispatch re-schedules the next doubling step.
2. **`session-status-handler.ts`** — after the retry-key dedupe, a retry message that does NOT classify as `quota_exceeded` logs `retry signal within same-model retry budget` and returns, so the provider's native same-model retry is never aborted for a non-quota signal. Quota signals still abort + fall back.
3. **`event-handler.ts`** — a terminal retryable `session.error` that is not `quota_exceeded` schedules a same-model retry (`session.error.same-model`) instead of advancing the fallback chain; `session.stop`/delete/idle and stale-session cleanup clear pending timers and attempt counters.
4. **`message-update-handler.ts`** — the assistant-error branch routes non-quota retryables through the same-model scheduler (this path could still switch models after the first two fixes); a visible assistant response clears the timer and resets the attempt counter.
5. **`auto-retry.ts`, `auto-retry-cleanup.ts`, `hook.ts`, `types.ts`** — wire the attempt/timer maps into hook deps and helper lifecycle; disposal and cleanup release timers.

Quota exhaustion (`quota_exceeded` / `usage limit` class) keeps the existing `dispatchFallbackRetry` + `fallback_models` behavior, including the TUI toast.

## Verification

Pattern (necessary, NOT sufficient — the pattern is a string literal that survives bundling even if the code path is unreachable):

```bash
grep -E "session\.error\.same-model" \
  /home/ezotoff/oh-my-openagent-v4.19.2/packages/omo-opencode/src/hooks/runtime-fallback/same-model-retry.ts   # 1
grep -c "session.error.same-model" /home/ezotoff/oh-my-openagent-v4.19.2/dist/index.js                          # 1
grep -c "quota_exceeded" /home/ezotoff/oh-my-openagent-v4.19.2/dist/index.js                                    # >= 5
```

Tests (source of truth for the routing contract):

```bash
cd /home/ezotoff/oh-my-openagent-v4.19.2
bun test packages/omo-opencode/src/hooks/runtime-fallback   # 257 pass, 0 fail
bun run --cwd packages/omo-opencode typecheck               # exit 0
```

## Runtime Verification

1. Confirm the server restarted onto the rebuilt dist: `ps -eo pid,lstart,etime,args | grep 'opencode serve'` shows a start time after the deploy, and `~/.local/share/opencode/logs/oh-my-opencode.log` receives fresh entries.
2. On the next real Z.AI concurrency throttle (`stream error ... "Rate limit reached for requests"`), the durable OMO log must show the request staying on `zai-coding-plan/glm-5.3-flash`: no `Preparing fallback` / `Auto-retrying with fallback model` for that session's non-quota error, and a scheduled same-model retry instead.
3. Quota check in the same window: a genuine `quota_exceeded` / `usage limit` error MUST still produce `Preparing fallback` and the `Model Fallback` toast with the `[agent:…session]` origin suffix.
4. Regression signal: any non-quota rate-limit error that produces `Preparing fallback`, or a same-model retry interval exceeding 120 s, means the patch is `runtime_effective: false` — record it in `## Runtime Status` and do NOT bump `dep_version`.
5. Until an observation lands, keep `runtime_effective: false` and report `Not verified live: same-model retry under real throttling`.

## Reapply Instructions

Source patch — reapply from fork commit `3d507e2de` (branch `fix/custom-patches-v4.19.2`; the full implementation in one commit).
Historical note: the original implementation commits (`754cec4ee`, `ea6656610`, `0cd9bde32`, `453c6894a`, `e6bb8b059`) were never pushed and are unrecoverable — do NOT cite them as reapply sources:

```bash
cd /home/ezotoff/oh-my-openagent-v4.19.2
git show 3d507e2de --stat            # same-model-retry.ts + types/state wiring + handler gates + tests
git cherry-pick 3d507e2de
bun run build                        # rebuild dist/index.js
# then re-apply the four dist-level patches (omo--durable-log-path,
# omo--fallback-toast-origin, omo--lookat-fallback-patience,
# omo--auto-slash-command-duplicate-user-args) per their own reapply
# instructions — this rebuild clobbers them.
bash /home/ezotoff/ez-omo-config/scripts/verify-live-patches.sh
```

On a future upstream refactor, the load-bearing anchors are: the quota gate immediately after the retry-key dedupe in `session-status-handler.ts`; the non-quota same-model branch in `event-handler.ts` (`scheduleSameModelRetry`) and in `message-update-handler.ts`; and the delay formula `min(1000 * 2**attempt, 120_000)` in `same-model-retry.ts`.

## Durable Alternative

An upstream `runtime_fallback` policy knob (e.g. `fallback_on: ["quota_exceeded"]` plus `same_model_retry: { base_ms, max_ms }`) would eliminate this patch. The classification already distinguishes `quota_exceeded` from generic retryables, so upstreaming a policy filter is additive and defaults-compatible. Status: not-yet-pursued — candidate for an upstream PR against `code-yeongyu/oh-my-openagent`.

## Runtime Status

**Deployed 2026-09-14 08:23:33Z; runtime effectiveness NOT yet observed.** Source tests (257/257), typecheck (exit 0), bundle embedding (`grep -c 'session.error.same-model' dist/index.js` = 1), and the regression corpus (26 pass / 26 kill-tests proved, including `023-quota-only-fallback`) are verified. `systemctl --user restart opencode.service` replaced the systemd server PID (port 3021: 328750 → 2405252, start 08:23:33Z) and the durable OMO log received fresh entries at 08:23:47Z, confirming the rebuilt dist is loaded.

**Known gap:** two non-systemd `opencode serve` processes remain on the pre-patch module in memory — PID 328751 (`--hostname 127.0.0.1 --port 3030`, since 00:37:44 local) and PID 2251581 (`--port 46946`, since 07:44:47Z). Bare-`opencode` TUI processes load OMO themselves, so sessions served by those PIDs keep the old fallback behaviour until those processes are restarted. New sessions on the systemd server are patched.

The behavior claim still awaits a real Z.AI concurrency throttle: no `Rate limit reached` stream error has occurred since the restart (checked 08:23:56Z). Flip `runtime_effective: true` only when step 2 of Runtime Verification is observed and record the timestamp + log lines here.
