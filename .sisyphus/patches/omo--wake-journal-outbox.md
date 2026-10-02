---
patch_id: "omo--wake-journal-outbox"
dependency: "oh-my-openagent"
target_file: "packages/omo-opencode/src/features/background-agent/manager.ts, packages/omo-opencode/src/features/background-agent/parent-wake-notifier.ts"
target_install_path: "/home/ezotoff/oh-my-openagent-v4.19.2"
source_repo: "/home/ezotoff/oh-my-openagent-v4.19.2"
status: "active"
applied_date: "2026-09-22"
dep_version: "4.19.2"
runtime_effective: true
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

Full source surface (audit inventory; verifier `target_file` lists the dispatch-wiring files that carry the live marker): wake-journal.ts, parent-wake-flush-runner.ts, parent-wake-prompt-dispatch.ts, parent-wake-pending-queue.ts, parent-wake-dedupe.ts, parent-wake-session-message.ts, parent-wake-notifier-types.ts, create-managers.ts.

Durable per-wake journal at `<dir>/.omo/run-continuation/wakes/<wakeID>.json` — state machine queued→dispatching→dispatched-awaiting-output→consumed|dead-letter, written BEFORE dispatch, atomic tmp→rename claim with generation counters, startup sweep, dead-letter never auto-replayed, capped watchdog (max 3 attempts, 10 min apart, exact-identity precondition). Identity via per-wake `<!-- OMO_WAKE:<id> -->` marker with normalized-hash fallback (WIP bug fixed: stored text carries `<!-- OMO_INTERNAL_INITIATOR -->`, exact-hash matching never matched). Source patch — fork commits 3bddbe701..3cd78e82351307428843269fb1d6bbe82beb3c88 on branch feature/wake-journal-outbox (pushed, verified via git branch -r --contains 2026-09-28). 2026-09-28 fix (3cd78e82): consumption leak root-caused — manager treated ANY session activity as consumption and the in-memory tracker could clear before exact-message output was observed; notifier/flush-runner now verify persisted output against the wake's exact user message before consuming, suppressed dispatches stay recoverable, identity-filtered startup recovery added. 31 targeted tests green; QA evidence .omo/evidence/20260928-wake-consumption/qa.md. Dist rebuilt in place 2026-09-28 15:50; runtime_effective flipped true 2026-10-02 after live consumption verified (see Runtime Verification; Branch A of .omo/plans/wake-redundancy-decision.md). Companion: R3 convergence/union guard in ez-omo-config restart-with-continuation.sh consumes non-terminal journal entries.

## Runtime Verification

runtime_effective: true — flipped 2026-10-02 (Branch A of .omo/plans/wake-redundancy-decision.md). The original flip bar (a real server crash mid-wake recovered by the journal) remains unproven; the plan's bar was live consumption, which is met: 65 wakes created after the 2026-09-28 15:50 dist rebuild reached `consumed` — all `shouldReply=true`, zero stranded reply-wakes. Session-local evidence (queued→dispatched→consumed, ~2–6 min transit), session ses_f0415bac6ffefZXg75KPyzo8s9 (ez-omo-config): .omo/run-continuation/wakes/e62cc533-626f-4b56-898b-bab52878451a.json, .omo/run-continuation/wakes/7db41bc7-6ab6-4607-8f25-6aa07ab11bf4.json, .omo/run-continuation/wakes/4cf86ab5-47a0-4cfb-9507-4eaf97e84c59.json.

Known residue (2026-10-02): `shouldReply=false` admit-only wakes systematically remain `dispatched-awaiting-output` (136 fresh at verification time) — no assistant turn exists to satisfy exact-output consumption; deadline/dead-letter enforcement for them unverified. Tracked read-only by scripts/check-wake-journal-growth.sh (6th ExecStart of opencode-patch-integrity-check.service, advisory). Crash-recovery path (watchdog replay / dead-letter) still unproven. Flip conditions for any future consumption-aware flush: wisdom "wake journal flip conditions" / .omo/plans/wake-redundancy-decision.md.

Observed 2026-09-22 (happy path, first live transit): wake d32d532e-a0c7-4082-9c9a-380fe55401c1 for ses_f39feb282ffeWDmiKNSHgpIrz7 (ez-omo-bench) written before dispatch, dispatched, consumed on real output — state machine + OMO_WAKE-marker identity verified on a real background-task completion. Crash-recovery path (watchdog replay / dead-letter) still unproven.
