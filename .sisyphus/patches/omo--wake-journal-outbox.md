---
patch_id: "omo--wake-journal-outbox"
dependency: "oh-my-openagent"
target_file: "packages/omo-opencode/src/features/background-agent/wake-journal.ts, parent-wake-notifier.ts, parent-wake-flush-runner.ts, parent-wake-prompt-dispatch.ts, parent-wake-pending-queue.ts, parent-wake-dedupe.ts, parent-wake-session-message.ts, parent-wake-notifier-types.ts, manager.ts, create-managers.ts"
target_install_path: "/home/ezotoff/oh-my-openagent-v4.19.2"
source_repo: "/home/ezotoff/oh-my-openagent-v4.19.2"
status: "active"
applied_date: "2026-09-22"
dep_version: "4.19.2"
runtime_effective: false
upstream_issue: "none"
verification_pattern: "consumeDispatchedParentWakeOutput"
verification_strength: "discriminative"
required_evidence: "runtime"
surfaces: "server-api"
---

# OMO wake-journal outbox (v3)

## Problem

Background-task completion wakes are lost when the server dies between prompt_async accept and delivery (2026-09-18 debate; ADOPTED v3 decision). Marker-scan recovery only covered a minority of crash windows (F2) and could not faithfully re-dispatch (F3).

## Patch Description

Durable per-wake journal at `<dir>/.omo/run-continuation/wakes/<wakeID>.json` — state machine queued→dispatching→dispatched-awaiting-output→consumed|dead-letter, written BEFORE dispatch, atomic tmp→rename claim with generation counters, startup sweep, dead-letter never auto-replayed, capped watchdog (max 3 attempts, 10 min apart, exact-identity precondition). Identity via per-wake `<!-- OMO_WAKE:<id> -->` marker with normalized-hash fallback (WIP bug fixed: stored text carries `<!-- OMO_INTERNAL_INITIATOR -->`, exact-hash matching never matched). Source patch — fork commits 3bddbe701..4bc6ccc59 on branch feature/wake-journal-outbox (pushed). Companion: R3 convergence/union guard in ez-omo-config restart-with-continuation.sh consumes non-terminal journal entries.

## Runtime Verification

runtime_effective: false — flip only after a real server crash mid-wake is recovered by the journal (wake file transitions to consumed and the session continues).
