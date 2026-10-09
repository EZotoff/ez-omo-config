---
patch_id: "opencode--stream-stall-watchdog"
dependency: "opencode"
target_file: "packages/opencode/src/session/processor.ts"
target_install_path: "/home/ezotoff/.opencode/bin/opencode"
source_repo: "/home/ezotoff/src/opencode"
status: "active"
applied_date: "2026-09-22"
dep_version: "1.18.31-p4"
runtime_effective: true
upstream_issue: "none"
verification_pattern: "LLM stream stalled for"
verification_strength: "discriminative"
required_evidence: "runtime"
surfaces: "server-api, cli-run, tui-interactive"
---

# OpenCode stream-stall watchdog

## Problem

2026-09-22 halt diagnosis RC1: a provider that accepts the connection then streams nothing (zai rate-limit storm) leaves the `Stream.runDrain` pipe unsettled — `Effect.retry(SessionRetry.policy(...))` only reacts to failures, so the session stays busy forever with a zero-token never-completed assistant message and NO error event (retry plugin sees nothing to intercept). Four top-level sessions wedged this way in one storm.

## Patch Description

Inactivity deadline around the LLM stream in `processor.ts`: `Effect.raceFirst(stream, watchdog)`; the watchdog fails with `ProviderError.ResponseStreamError` after `OPENCODE_STREAM_STALL_MS` (default 600000) of no `Stream.tap` event. `MessageV2.fromError` maps that to a retryable `APIError`, so the existing retry/fallback machinery engages. User aborts interrupt the race (watchdog never fires); `onInterrupt` guard skips halt when stalled/settled. Regression: `test/stalled-stream.test.ts`.

## Runtime Verification

runtime_effective: true — flipped 2026-09-28 on verified organic evidence: 91 messages with error "LLM stream stalled for 600000ms" (isRetryable=true, ProviderResponseStreamError) spanning 2026-08-28..2026-09-28 across top-level and child sessions on all surfaces; 35/40 sampled fires show a same-attempt recovery chain (stall error, then assistant completion with output>0, no intervening user prompt). Residual gap (bounded, understood): stalls in flight when a server process dies never fire the in-process watchdog — 24 such orphaned message rows since Sep 25 all cluster within minutes before known restarts (13 main) or on the bench unit that ran a pre-patch binary until Sep 27 11:11 (11). No keep-alive-blindness observed in field data.
