---
patch_id: "omo--parent-wake-idle-deferral-ceiling"
dependency: "oh-my-openagent"
target_file: "packages/omo-opencode/src/features/background-agent/parent-wake-flush-runner.ts"
target_install_path: "/home/ezotoff/oh-my-openagent-v4.19.2"
status: "active"
applied_date: "2026-10-07"
dep_version: "4.19.2"
upstream_issue: "none"
verification_pattern: "idle-deferral ceiling \(history guards bypassed\)"
surfaces: ["server-api"]
runtime_effective: false
note: "Source patch, carried as fork commit 50912c476 (branch fix/custom-patches-v4.19.2, pushed to EZotoff/oh-my-openagent 2026-10-07). status: active — dist rebuilt (build receipt ~/.local/share/opencode/builds/omo-dist-50912c476a.json) and both servers restarted 2026-10-07 21:19:57/21:20:17 CEST. runtime_effective: false until a real idle-stalled wake is observed recovering via the 'Sent parent wake after idle-deferral ceiling' log line."
---

# Parent-Wake Idle-Deferral Ceiling

## Problem

A reply-required parent wake queued behind an **idle** parent session whose last
assistant turn looks like a pending tool turn (aborted stream, empty trailing
assistant output, un-inspectable messages) was held **forever** by two
compounding guards:

1. `getParentWakeSessionHistoryDeferralDecision` defers ("latest assistant turn
   blocks internal prompts" / "Holding parent wake during stale tool-call
   deferral");
2. `deferReplyWakeWhileUnsafe` then holds the retained reply-required wake
   ("Deferred retained reply-required parent wake until parent session is
   safe") and reschedules every ~1s.

The existing 60s force-dispatch ceiling (`shouldForceDispatchAfterActiveDefer`)
only bypasses these guards while `sessionActive === true`. An idle parent has
no in-flight turn to fork, so holding there is a pure deadlock. Incident:
ses_ef45bab34ffenpIPZTQomDmsQ9, 2026-10-07 19:00:00–19:02:24Z — the wake spun
"Deferred retained reply-required" every second for 80+s and escaped only
because a status check happened to flip; without that luck the session stalls
permanently on the "ALL BACKGROUND TASKS COMPLETE" nudge (the reported
recurring symptom). The 2026-10-05 terminal-only-wakes rework
(omo--subagent-fallback-inplace) reduced wake count but did not bound this
hold loop — that is the gap this patch closes.

## Patch Description

In `ParentWakeFlushRunner.flushPendingParentWake` (fork commit `50912c476`):

- New `forceDispatchIdleCeiling = !sessionActive && shouldForceDispatchAfterActiveDefer(wake)`
  (shouldReply && queuedAge ≥ 60s, queuedAt survives requeues).
- Both history-deferral branches (`toolWaitDecision.defer`,
  `finalToolWaitDecision.defer`) are bypassed when the ceiling fires, falling
  through to a full reply dispatch with
  `skipPromptGateStatusCheck: true` and `skipPromptGateToolStateCheck: true`.
- Busy-session behavior is UNCHANGED (existing ceiling test
  "retained noReply wake ages while parent is busy → does not force a reply"
  still passes): a live turn can still be running, so holding remains correct.
- Fresh user-message-in-progress deferral is also unchanged (user-race guard,
  issue #4120); the wake keeps aging and force-dispatches once that turn ends.
- New log line on recovery: `Sent parent wake after idle-deferral ceiling
  (history guards bypassed)`.

Regression tests: `parent-wake-idle-deferral-ceiling.test.ts` (3 tests:
young idle wake admits noReply + retains; aged idle wake force-dispatches a
reply and clears the queue; aged busy wake still holds).

## Verification

```bash
grep -c 'idle-deferral ceiling (history guards bypassed)' \
  /home/ezotoff/oh-my-openagent-v4.19.2/dist/index.js
# Expected: 1

cd ~/oh-my-openagent-v4.19.2/packages/omo-opencode && \
  bun test src/features/background-agent/parent-wake-idle-deferral-ceiling.test.ts \
           src/features/background-agent/parent-wake-active-defer-ceiling.test.ts
# Expected: 6 pass (3 new + 3 existing ceiling tests)
```

Background-agent suite: 761 pass / 6 fail — the 6 failures are pre-existing on
clean HEAD (verified via `git stash -u`), unchanged by this patch. `tsgo
--noEmit -p packages/omo-opencode/tsconfig.json` clean.

## Runtime Verification

1. Reproduce shape: parent session ends a turn with a dead/aborted final
   assistant message while a background task completes → wake queued.
2. Within ~60s of queue age with the parent still idle, the log must show
   `Sent parent wake after idle-deferral ceiling (history guards bypassed)`
   and the parent must produce a continuation turn.
3. On first live observation, flip `runtime_effective: true` here and record
   the timestamp + session ID.

Not verified live: runtime_loaded (servers restarted with the patched dist,
plugin loaded with zero `failed to load plugin` lines — but no real stall has
yet exercised the new ceiling path).

## Reapply Instructions

Source patch — reapply from fork commit `50912c476` (branch
`fix/custom-patches-v4.19.2`), rebuild with `bun run build`, restart both
opencode servers via `restart-with-continuation.sh`.

## Related

- `omo--subagent-fallback-inplace` — the 2026-10-05 wake rework this completes.
- opencode--sse-directory-filter-removal — the separate TUI invisibility of
  wake continuations (why stalls look like silent dead sessions).



## Verification-pattern fix (2026-10-09)

verification_pattern previously used unescaped parentheses — the verifier treats patterns as regex, so a group can never match the literal "(history guards bypassed)" text. Escaped to \\(...\\). Patch content itself was present and unaffected.
