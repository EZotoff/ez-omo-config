---
patch_id: "omo--remove-activity-stagnation-bypass"
dependency: "oh-my-openagent"
target_file: "src/hooks/todo-continuation-enforcer/session-state.ts"
target_install_path: "/home/ezotoff/oh-my-openagent-v4.12.1"
status: "upstreamed"
applied_date: "2026-04-10"
dep_version: "4.12.1"
upstream_issue: "none"
verification_pattern: "\"none\" \\| \"todo\""
upstream_commit: "df7e1ae1 (Mar 17 2026, YeonGyu-Kim)"
note: "Dropped on v4.12.1 update. Upstream shipped the same fix 24 days before the local fork patch. All 5 patched symbols absent from v4.12.1. progressSource type is 'none' | 'todo' (no 'activity' member) in both upstream and patched state."
---

# Remove Activity-Based Stagnation Bypass in TODO Continuation

## Problem
The todo-continuation-enforcer's stagnation detector was supposed to stop continuation after 3 cycles without progress (`MAX_STAGNATION_COUNT = 3`). However, any tool call (compress, grep, bash) incremented `activitySignalCount`, which was treated as "activity progress" in `trackContinuationProgress()`. This reset `stagnationCount` to 0 every cycle, so stagnation never reached the threshold. The result: an infinite continuation loop when GLM-5.1 degraded to minimal responses in long sessions — the model would just call compress/grep, output `<promise>DONE</promise>`, and get re-prompted forever.

## Patch Description
Removed all activity-based progress detection. Stagnation now only tracks actual todo state changes (incomplete count decrease, completed count increase, todo snapshot change).

**Files changed (5):**
- `session-state.ts` — Removed `activitySignalCount`, `lastObservedActivitySignalCount`, `recordActivity()`, `ContinuationProgressOptions` usage, `hasObservedExternalActivity` check. Changed `progressSource` type from `"none" | "todo" | "activity"` to `"none" | "todo"`.
- `non-idle-events.ts` — Removed all 5 `sessionStateStore.recordActivity()` calls.
- `idle-event.ts` — Removed `shouldAllowActivityProgress()` function and `allowActivityProgress` option.
- `types.ts` — Removed `ContinuationProgressOptions` interface.
- `session-state.test.ts` — Replaced 2 activity-based tests with 1 test proving stagnation works correctly.

## Verification
```bash
grep -n '"none" | "todo"' /home/ezotoff/omo-hub/projects/oh-my-openagent/src/hooks/todo-continuation-enforcer/session-state.ts && echo "APPLIED" || echo "STALE"
```
Additionally, confirm removal:
```bash
grep -c "hasObservedExternalActivity\|recordActivity\|allowActivityProgress" /home/ezotoff/omo-hub/projects/oh-my-openagent/src/hooks/todo-continuation-enforcer/session-state.ts | grep -q "^0$" && echo "APPLIED" || echo "STALE"
```

## Reapply Instructions
1. In `session-state.ts`:
   - Remove `activitySignalCount` and `lastObservedActivitySignalCount` from `TrackedSessionState`
   - Remove `recordActivity()` function, its interface entry, and its return value
   - Remove `ContinuationProgressOptions` import
   - In `trackContinuationProgress()`: remove `options` parameter, remove `currentActivitySignalCount` and `hasObservedExternalActivity` variables, remove `trackedSession.lastObservedActivitySignalCount` assignment
   - Change progress detection from `progressSource = ... hasObservedExternalActivity ? "activity" : "none"` to simple boolean `hasProgressed = incompleteCount < previousIncompleteCount || hasCompletedMoreTodos || hasTodoSnapshotChanged`
   - Change `ContinuationProgressUpdate.progressSource` type to `"none" | "todo"`
   - Remove activity resets from `resetContinuationProgress()`
2. In `non-idle-events.ts`: Remove all `sessionStateStore.recordActivity()` calls
3. In `idle-event.ts`: Remove `shouldAllowActivityProgress()` function and `{ allowActivityProgress: ... }` option from `trackContinuationProgress()` call
4. In `types.ts`: Remove `ContinuationProgressOptions` interface
5. In `session-state.test.ts`: Remove/replace activity-based test cases

## Durable Alternative
Upstream to oh-my-openagent repository via PR. The activity-based progress detection was a design flaw — tool calls should never count as "progress" for stagnation purposes.
Status: not-yet-pursued
