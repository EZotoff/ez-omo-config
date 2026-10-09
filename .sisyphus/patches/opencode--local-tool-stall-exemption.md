---
patch_id: "opencode--local-tool-stall-exemption"
dependency: "opencode"
target_file: "packages/opencode/src/session/processor.ts"
target_install_path: "/home/ezotoff/.opencode/bin/opencode"
source_repo: "/home/ezotoff/src/opencode"
status: "active"
applied_date: "2026-10-09"
dep_version: "1.18.31-p4"
runtime_effective: false
upstream_issue: "none"
verification_pattern: "stream-stall heartbeat: local tool execution in flight"
verification_strength: "discriminative"
required_evidence: "runtime"
surfaces: ["server-api", "cli-run", "tui-interactive"]
---

# OpenCode local-tool stall exemption (stream-stall watchdog heartbeat)

Note on `surfaces`: `processor.ts` is server-side core consumed by every surface (server-api, cli-run, tui-interactive); it is NOT a rendering-directory path. Listed for completeness per TEMPLATE guidance.

## Problem

The AI SDK executes locally-run tools (question dialogs, permission prompts, long bash commands, subagent `task` waits, `background_output`) INSIDE the LLM stream, between `tool-call` and `tool-result`/`tool-error`. That interval produces no stream events, so the stream-stall watchdog (`opencode--stream-stall-watchdog`, active) fires after `OPENCODE_STREAM_STALL_MS` (default 600 s) and retries the whole request — while a user question or permission dialog is legitimately pending. Symptom: the agent re-asks its question every ~10 minutes (duplicate question dialogs, wedge-retry loops; wisdom `20260929-013231-zydr`).

Prior art: the reverted question-guard patch (`opencode--question-stream-stall-guard`, superseded 2026-09-30, revert `4d8d4713fa`) tried a tool-NAME-list-based pause of the watchdog and failed for two reasons: (a) unbounded name-keyed suspension created immortal orphan sessions; (b) ANY modification of the watchdog `while(true)` block miscompiles under the Bun bundler (TDZ `ReferenceError`, silent stream hangs 0/3 in scratch A/B — wisdom `20260930-084226-qyuf`).

## Patch Description

Rung R1 (chosen; R2/R3 fallback ladders defined but not needed — A/B gate passed on R1): heartbeat refresh while locally-executed tools are in flight, with the watchdog `while(true)` block left byte-identical.

Mechanism in `SessionProcessor.process` inner `Effect.gen`:
1. `const localTools = new Set<string>()` immediately after the `lastEvent` clock declaration.
2. Tracking inside the existing `Stream.tap` between the clock reset and `handleEvent(event)`: on `tool-call` with `!event.providerExecuted` → `localTools.add(event.id)`; on `tool-result`/`tool-error` → `localTools.delete(event.id)`. Ordering covers the doom-loop `permission.ask` inside `handleEvent` (`processor.ts:376`) and all tool-level `ctx.ask` prompts.
3. A `heartbeat` const after the `watchdog` const (block untouched): sleeps `stall/2`, and while `localTools.size > 0` refreshes `lastEvent` and emits `Effect.logWarning("stream-stall heartbeat: local tool execution in flight", ...)`.
4. Race site nested: `Effect.raceFirst(stream.pipe(...), Effect.raceFirst(watchdog, heartbeat))`.

Rationale vs the reverted attempt: no tool-name list (any local tool is exempt — question, task, bash, background_output); no edit to the TDZ-trapped watchdog block; refresh keyed on the `providerExecuted` event field so provider-side silence (first-byte hang, mid-stream death, provider-executed tools, post-`tool-result` next-request hang) keeps the full unchanged deadline. Accepted residual: an abandoned dialog now holds a busy session until aborted (same as any human wait), observable via the heartbeat warning log.

Fix commit `acc3dc0eb6` on fork branch `fix/v1.18.31-local-tool-stall-exemption` (+ typecheck-fixups `8869609556`, `2963887d1b`), base = p3 source_head `3e77f50399`.

## Verification

Pattern (necessary, NOT sufficient): `grep -ac 'stream-stall heartbeat: local tool execution in flight' /home/ezotoff/.opencode/bin/opencode`. The literal is a minification-survivor string unique to this patch (discriminative) but cannot prove runtime effectiveness. Structural regression pair: `bash tests/regressions/2026-10-09-local-tool-stall-exemption.sh` and `bash tests/regressions/2026-10-09-local-tool-stall-exemption.kill.sh` (polarity).

## Runtime Verification

1. RED (pre-patch p3): `bash tests/smoke/smoke-local-tool-stall-exemption.sh --bin ~/.opencode/bin/opencode --expect stall` — long bash tool with `OPENCODE_STREAM_STALL_MS=15000` must show `LLM stream stalled for 15000ms` (defect reproduced).
2. GREEN (p4, task 13): `bash tests/smoke/smoke-local-tool-stall-exemption.sh --bin ~/.opencode/bin/opencode --expect clean` — sleep 45 s tool completes, no stall error, wall > 45 s.
3. Not-masked (p4, task 13): `bash tests/smoke/smoke-stall-catch-preserved.sh --bin ~/.opencode/bin/opencode` — hanging mock provider with `OPENCODE_STREAM_STALL_MS=15000` must still surface `LLM stream stalled for 15000ms`.
4. Pending operator check (non-gating): interactive TUI question dialog held > stall window with reduced `OPENCODE_STREAM_STALL_MS` (headless `opencode run` has no question tool — wisdom `20260929-060436-xg5q`).
5. runtime_effective stays false until (2) and (3) are GREEN on the installed binary; smoke records go to `~/.local/share/opencode/smoke-results/<p4-sha>.json` (smoke id `local-tool-stall-exemption`).

## Reapply Instructions

1. From `/home/ezotoff/src/opencode`: `git worktree add <wt> -b <fix-branch> <receipt source_head>` (build NEVER in the dirty main checkout; never from dev).
2. Apply the `processor.ts` hunk from fork commit `acc3dc0eb64171dee2368856ace50e1172c124bc` (branch `fix/v1.18.31-local-tool-stall-exemption` on `EZotoff/opencode`). Do NOT edit the watchdog `while(true)` block — TDZ miscompile trap (wisdom `20260930-084226-qyuf`).
3. A/B gate before any install: 3× plain `run` probes + exemption probe (`OPENCODE_STREAM_STALL_MS=4000`, `sleep 12` tool, no stall error) + `grep -a 'LLM stream stalled for'` still embedded.
4. Build: `cd packages/opencode && OPENCODE_VERSION=<p-next> bun run script/build.ts --single --skip-install --skip-embed-web-ui`; verify version string exact and both grep markers ≥ 1.
5. Swap with servers stopped (continuation hooks), backup first, then run the Runtime Verification smokes.

## Durable Alternative

Upstream: the AI SDK exposing tool-execution windows or watchdog-relevant hooks so the processor can distinguish local-execution silence from provider silence without a local heartbeat. Status: not-yet-pursued.
