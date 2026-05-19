---
patch_id: "omo--boulder-worktree-authoritative-state"
dependency: "oh-my-openagent"
target_file: "src/hooks/atlas/resolve-active-boulder-session.ts"
target_install_path: "/home/ezotoff/omo-hub/projects/oh-my-openagent"
status: "active"
applied_date: "2026-05-19"
dep_version: "current"
upstream_issue: "none"
verification_pattern: "progress.isComplete === true"
---

# Boulder Worktree Authoritative Execution Root

## Problem

In OpenCode session `ses_1cd254116ffeSgwfviCkD5CG9q`, Boulder continuation entered an infinite loop beginning at message `msg_e330c8260001kuZGMf7gQX8rTt`, `2026-05-16T23:08:38.368Z`. The worktree plan had been fully completed (12/12), but the base repo Boulder state still showed the old base plan as 0/12 incomplete.

Root cause: OMO's Boulder continuation paths resolved progress from `ctx.directory` (the display/session directory, which was the base repo) instead of the actual execution root (the worktree). The idle hook, retry scheduler, and continuation injector all read base repo `.sisyphus/boulder.json`, saw `0/12` unchecked tasks, and repeatedly injected continuation prompts. The worktree's own `.sisyphus/boulder.json` correctly pointed to the completed worktree plan, but no code path consulted it.

## Patch Description

Introduces a centralized execution-root-aware Boulder resolver and wires all continuation paths through it. When `worktree_path` is present in base state and the worktree contains valid Boulder state with an `active_plan` inside the worktree, the worktree plan progress becomes authoritative. If state is ambiguous or inconsistent, continuation is suppressed (fail closed).

**Files changed (10 source + test files):**
- `src/hooks/atlas/resolve-active-boulder-session.ts` — Core resolver. Reads base state, then if `worktree_path` is valid, reads worktree Boulder state and validates `active_plan` is inside the worktree with matching plan name. Returns execution context with `displayDirectory`, `effectiveDirectory`, `boulderState`, `boulderStatePath`, `activePlan`, `progress`, `worktreePath`, `isConsistent`, and `failureReason`.
- `src/hooks/atlas/types.ts` — Resolver return type additions (`ResolvedBoulderContext`, `BoulderContextFailureReason`).
- `src/features/boulder-state/types.ts` — Optional legacy-compatible fields on `BoulderState`: `state_version`, `execution_root`, `display_directory`.
- `src/hooks/atlas/idle-event.ts` — `handleAtlasSessionIdle`, `injectContinuation`, `scheduleRetry` now use the centralized resolver. `injectContinuation` recomputes authoritative progress immediately before prompt construction and skips if complete or invalid. `readCurrentTopLevelTask` and `getTaskSessionState` read from effective directory, not blindly `ctx.directory`.
- `src/hooks/atlas/boulder-continuation-injector.ts` — Prompt `query.directory` remains `ctx.directory` to preserve visible session behavior, but receives authoritative `worktreePath` and progress from resolved context.
- `src/cli/run/continuation-state.ts` — CLI completion state respects authoritative worktree progress; reports inactive when worktree plan is complete even if base is incomplete.
- `src/hooks/start-work/context-info-builder.ts` — `/start-work --worktree` writes canonical Boulder state in worktree with `execution_root` and `display_directory` provenance.
- `src/hooks/start-work/start-work-hook.ts` — Start-work hook entry points updated to persist worktree-authoritative state.
- `src/hooks/start-work/worktree-detector.ts` — Worktree path validation for resolver consumption.
- Test files under `src/hooks/atlas/`, `src/hooks/start-work/`, `src/features/boulder-state/`, `src/cli/run/` — Regression tests covering base `0/12` + worktree `12/12` mismatch, deleted worktree, plan-name mismatch, active-plan-outside-worktree, and CLI continuation inactive.

**Preserved behavior**: `plugins/worktree.ts` in ez-omo-config intentionally creates worktree sessions with `query: { directory: mainWorktreePath }` (the base repo directory) so the session remains visible in the main TUI. This is a UX choice, not a bug. The fix does not change this; instead, OMO's resolver distinguishes `displayDirectory` from `effectiveDirectory` so continuation logic uses the worktree root while UI/session visibility stays on the base repo.

## Invariants Protected

1. `ctx.directory` is display directory, not necessarily execution directory.
2. Worktree state is authoritative when valid.
3. Fail closed on ambiguous or inconsistent state (no injection).
4. Never inject continuation from stale cross-root progress.
5. Main-TUI worktree session visibility is preserved.

## Verification

From `/home/ezotoff/omo-hub/projects/oh-my-openagent`, these commands must exit `0` with no failed tests:

```bash
bun test src/hooks/atlas/resolve-active-boulder-session.test.ts
bun test src/hooks/atlas/boulder-continuation-injector.test.ts
bun test src/features/boulder-state/storage.test.ts
bun test src/hooks/start-work/index.test.ts src/hooks/start-work/worktree-detector.test.ts
bun test src/cli/run/completion-continuation.test.ts src/cli/run/continuation-state.json-backend.test.ts src/cli/run/continuation-state-marker.test.ts
```

Broader regression suite:
```bash
bun test src/hooks/atlas src/hooks/start-work src/features/boulder-state src/cli/run
```
(Note: 4 pre-existing failures in unrelated agent-naming tests in `src/hooks/atlas/index.test.ts`)

Key assertions:
- `promptAsyncMock` is called `0` times when base state says `0/12` but authoritative worktree plan says `12/12`.
- Resolver returns `progress.total === 12`, `progress.completed === 12`, `progress.isComplete === true` for the complete worktree fixture.
- In worktree-active mode, resolver never uses base-repo plan progress when a valid worktree Boulder/plan exists.
- If state is ambiguous or inconsistent, no continuation directive is injected.

## Reapply Instructions

1. Apply Task 1 (contract/types) changes:
   - Extend `src/hooks/atlas/types.ts` with resolver return type
   - Add optional fields to `src/features/boulder-state/types.ts`
2. Apply Task 2 (resolver) changes:
   - Implement worktree-aware resolution in `src/hooks/atlas/resolve-active-boulder-session.ts`
3. Apply Task 3 (wiring) changes:
   - Update `src/hooks/atlas/idle-event.ts` to use resolver
   - Update `src/hooks/atlas/boulder-continuation-injector.ts` to accept resolved context
   - Update `src/cli/run/continuation-state.ts` for worktree authority
4. Apply Task 4 (start-work) changes:
   - Update `src/hooks/start-work/context-info-builder.ts`, `start-work-hook.ts`, `worktree-detector.ts`
5. Apply Task 5 (tests) changes:
   - Add regression tests across all affected modules
6. Run `bun run build` to regenerate dist artifacts
7. Restart OpenCode to load rebuilt OMO plugin

## Durable Alternative

Upstream to oh-my-openagent repository. The core issue is that Boulder continuation resolves progress from session display directory rather than execution root. A proper upstream fix would either:
- Make `ctx.directory` always reflect the execution root (breaking change, affects many hooks), or
- Provide an official execution-root API that all continuation paths consult.

Status: not-yet-pursued

## Evidence State

| State | Status | Notes |
|-------|--------|-------|
| repo_implemented | ✅ Yes | OMO source changes and patch file exist |
| tests_passed | ✅ Yes | All targeted tests pass (5/5 commands exit 0). Broad suite: 429/433 pass; 4 failures are pre-existing unrelated agent-naming tests |
| live_file_installed | Not verified | OMO dist not yet rebuilt with patch |
| active_config_registered | Not verified | OMO plugin not yet loaded with patch |
| runtime_loaded | Not verified | No runtime invocation of patched code yet |
| real_project_behavior_proven | Not verified | No controlled worktree session proof yet |

**Not verified live: live_file_installed, active_config_registered, runtime_loaded, real_project_behavior_proven.**
