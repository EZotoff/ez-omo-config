---
patch_id: "opencode--question-stream-stall-guard"
dependency: "opencode"
target_file: "packages/opencode/src/session/processor.ts"
target_install_path: "/home/ezotoff/.opencode/bin/opencode"
source_repo: "/home/ezotoff/src/opencode"
status: "superseded"
applied_date: "2026-09-28"
dep_version: "1.18.31-p2"
runtime_effective: false
upstream_issue: "none"
verification_pattern: "mcp_question"
verification_strength: "discriminative"
required_evidence: "provenance"
---

# OpenCode question-aware stream stall guard

## Problem

The AI SDK executes question-family tools inside the LLM stream. An unanswered question produces no stream events; after 600 seconds the existing stream-stall watchdog fails and retries the entire step, generating another question dialog while the first remains open.

## Patch Description

Source commit `48eedf9406659245bdf6af574bdcdd01766b15fc` on fork branch `fix/v1.18.31-question-stall-watchdog` tracks question-family tool call IDs (`question`, `AskUserQuestion`, `ask_user_question`, `askuserquestion`, `mcp_question`, case-insensitive) from `tool-call` to `tool-result`/`tool-error`. While any such call is outstanding, the existing watchdog re-arms instead of failing. Ordinary stream stalls keep the same deadline and retry path.

## Verification

Pattern (necessary, NOT sufficient): `grep -ac 'mcp_question' /home/ezotoff/.opencode/bin/opencode`. The literal proves the candidate code is embedded but not that a waiting question reaches it. Run `bash tests/regressions/2026-09-28-question-stream-stall.sh` and the paired `.kill.sh`; those checks are structural only.

## Runtime Verification

1. Run `opencode run --dir "$scratch"` from a fresh scratch directory with `OPENCODE_STREAM_STALL_MS=15000` on a model instructed to call `question` (or `AskUserQuestion`) and wait for the user to answer. Keep the dialog unanswered for more than 15 seconds.
2. Inspect session message parts and status events. Exactly one question call must remain pending and there must be no `LLM stream stalled` retry while waiting; after answering, that same call must settle and the turn resume.
3. In a separate no-question stream-stall scenario, the ordinary retry must still occur after the configured inactivity deadline.
4. This real behavior has not yet been observed. Keep `runtime_effective: false` until the question-wait and ordinary-stall paths are exercised on the installed binary.

## Reapply Instructions

1. Check out the exact installed OpenCode release tag and the fork's required patch ancestry; do not build from dev.
2. Reapply the `processor.ts` change from fork commit `48eedf9406659245bdf6af574bdcdd01766b15fc` at the stream event handler and watchdog in `SessionProcessor.process`.
3. Run targeted processor tests, update the patch lockfile, build with the matching `OPENCODE_VERSION`, then use the transactional installer and verify both servers restarted.

## Durable Alternative

The watchdog is inside the binary's stream processor and has no plugin/config hook for identifying inline question waits. Upstreaming this guard would remove the local rebuild requirement. Status: not-yet-pursued.

## Supersession (2026-09-30)

REVERTED by commit 4d8d4713fa (fix/v1.18.31-question-stall-watchdog): the
suspension suspended the stall watchdog FOREVER while any question-family
tool was in flight — orphaned permission dialogs created immortal busy
sessions holding transcripts/streams in RAM (the parallel-session death
spiral amplifier). Additionally, ANY modification to that watchdog block
miscompiles under the Bun bundler (TDZ ReferenceError 'de' in production;
silent stream hangs 0/3 in scratch A/B). Deletion-only revert restores the
Sep-27-known-good timeout+retry semantics. Do NOT re-patch this region
without addressing the bundler miscompile first.
