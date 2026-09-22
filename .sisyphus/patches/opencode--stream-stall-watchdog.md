---
patch_id: "opencode--stream-stall-watchdog"
dependency: "opencode"
target_file: "packages/opencode/src/session/processor.ts"
target_install_path: "/home/ezotoff/.opencode/bin/opencode"
source_repo: "/home/ezotoff/src/opencode"
status: "active"
applied_date: "2026-09-22"
dep_version: "1.18.31-p2"
runtime_effective: false
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

runtime_effective: false — flip only after a real session recovers from an organic provider stall via the watchdog (log line "LLM stream stalled for", then a successful retry).
