---
patch_id: "omo--subagent-fallback-inplace"
dependency: "oh-my-openagent"
target_file: "packages/omo-opencode/src/features/background-agent/fallback-retry-handler.ts, packages/omo-opencode/src/features/background-agent/attempt-lifecycle.ts, packages/omo-opencode/src/features/background-agent/manager.ts, packages/omo-opencode/src/features/background-agent/manager.test.ts, packages/omo-opencode/src/features/background-agent/fallback-retry-handler.test.ts, packages/omo-opencode/src/features/background-agent/error-classifier.ts, packages/omo-opencode/src/features/background-agent/atlas-subagent-fallback-retry.test.ts, packages/omo-opencode/src/features/background-agent/background-task-notification-template.ts, packages/omo-opencode/src/features/claude-code-session-state/state.ts, packages/omo-opencode/src/hooks/runtime-fallback/fallback-retry-dispatcher.ts, packages/omo-opencode/src/hooks/runtime-fallback/fallback-retry-dispatcher.test.ts, packages/omo-opencode/src/hooks/runtime-fallback/message-update-handler.ts, packages/omo-opencode/src/hooks/runtime-fallback/subagent-quota-abort.test.ts, packages/model-core/src/runtime-fallback-error-classifier.ts, packages/model-core/src/model-error-classifier.test.ts"
target_install_path: "/home/ezotoff/oh-my-openagent-v4.19.2"
status: "active"
applied_date: "2026-10-05"
dep_version: "4.19.2"
upstream_issue: "none"
verification_pattern: "EZ-PATCH: subagent-fallback-inplace"
surfaces: ["server-api"]
runtime_effective: false
note: "Source patch, carried as fork commits e01423907, 74ab94f97, a71b9b345, 24cf5f9b0 (branch fix/custom-patches-v4.19.2, pushed to EZotoff/oh-my-openagent 2026-10-05). status: active — dist rebuilt with the EZ-PATCH marker and the fork branch pushed before activation (AGENTS.md rule 8). runtime_effective: false until the in-place hop is observed on a real fallback (todo 8)."
---

# Subagent Fallback Rework (in-place model fallback, terminal-only wakes, single-owner race guard, quota-abort pins)

## Problem

Four defects in OMO's background-subagent (task) fallback machinery, observed in the subagent-fallback-rework plan (2026-10-05):

1. **Fresh-session fallback for task attempts**: when a task session hit a fallback-eligible error, `tryFallbackRetry` always launched a NEW child session on the fallback model. The task's accumulated context (tools, partial output) was abandoned; the parent received a synthetic continuation from a context-free session.
2. **Per-hop parent wakes**: every fallback hop dispatched a parent notification, spamming the parent with N intermediate wakes for what is logically one logical attempt chain.
3. **Two-owner race on task-managed sessions**: the runtime-fallback hook (`a71b9b345` scope) could concurrently drive fallback on a session that the background-agent manager already owns, double-aborting and fighting over attempt state; hard-quota `session.error`s left tasks hanging in `running` forever because the error was classified transient.
4. **Error-classification gaps**: codex "No selectable account / not entitled" errors were not pinned as quota-class retryable; weekly-usage-limit shapes had no explicit classifier coverage.

## Patch Description

**Files changed (15):** source patch in the fork across four commits (branch `fix/custom-patches-v4.19.2`):

1. `e01423907` — in-place model fallback for task attempts: `fallback-retry-handler.ts` gains an in-place hop that re-prompts the SAME child session on the fallback model (prompt-async gate reservation + bounded reserved-retry loop mirroring auto-retry-dispatch), guarded by `hasVisibleAssistantResponse` visibility probe; `attempt-lifecycle.ts` / `manager.ts` rework attempt bookkeeping so a failed in-place acceptance fails the task cleanly (no fall-through to fresh after bookkeeping); `background-task-notification-template.ts` chain summaries.
2. `74ab94f97` — terminal-only parent wakes: `tryFallbackRetry` no longer wakes the parent per hop; only the terminal outcome notifies, with `formatAttemptChainSummary` appended.
3. `a71b9b345` — single-owner race guard + quota-abort finalization: resolver/emitter registry in `claude-code-session-state/state.ts`; the manager registers a managed-session resolver and synthetic-error emitter; the runtime-fallback dispatcher (`fallback-retry-dispatcher.ts`, `message-update-handler.ts`) defers task-managed sessions to the background-agent owner; hard quota/entitlement patterns added to `TERMINAL_SESSION_ERROR_PATTERNS` (`error-classifier.ts`) so quota session.errors finalize tasks.
4. `24cf5f9b0` — error-class pins: `/no\s+selectable\s+account/i` + `/not\s+entitled/i` in `model-core/runtime-fallback-error-classifier.ts` quota_exceeded branch; test pins in `model-error-classifier.test.ts` + `subagent-quota-abort.test.ts`.

## Verification

```bash
# Source (necessary and sufficient for a source patch):
grep -rc "EZ-PATCH: subagent-fallback-inplace" /home/ezotoff/oh-my-openagent-v4.19.2/packages/omo-opencode/src /home/ezotoff/oh-my-openagent-v4.19.2/packages/model-core/src   # >= 1 across the changed files
# Fork commits present:
git -C /home/ezotoff/oh-my-openagent-v4.19.2 log --oneline 3d507e2de..HEAD   # 4 commits ending 24cf5f9b0
# Tests:
cd /home/ezotoff/oh-my-openagent-v4.19.2 && bun test packages/omo-opencode/src/features/background-agent packages/omo-opencode/src/hooks/runtime-fallback packages/model-core/src/model-error-classifier.test.ts
```

## Runtime Verification

Behavioral patch (not a rendering/monkey patch); `surfaces: ["server-api"]` — the sufficient check is observing the in-place hop on a REAL subagent fallback:

1. Rebuild dist and restart: `cd /home/ezotoff/oh-my-openagent-v4.19.2 && bun run build`, then `systemctl --user restart opencode.service opencode-interactive.service`; confirm server start time changed (`ps -eo pid,lstart,args | grep 'opencode serve'`).
2. Trigger a real fallback-eligible error in a background subagent task (e.g. quota/429 on the primary model).
3. Expected: the durable OMO log (`~/.local/share/opencode/logs/oh-my-opencode.log`) shows the in-place hop re-prompting the SAME child session (no new child session created for hop 1), the parent receiving ONE terminal wake (not one per hop), and a hard-quota error finalizing the task (task leaves `running`).
4. Regression signal: a fresh child session spawned on hop 1, multiple parent wakes per chain, or a quota-failed task stuck in `running`.
5. On observation, flip `runtime_effective: true` and record the timestamp in a `## Runtime Status` section.

## Reapply Instructions

Source patch — reapply from fork commits (branch `fix/custom-patches-v4.19.2`):

```bash
cd /home/ezotoff/oh-my-openagent-v4.19.2
git log --oneline 3d507e2de..HEAD          # e01423907, 74ab94f97, a71b9b345, 24cf5f9b0
git cherry-pick e01423907^..24cf5f9b0      # on the next-version patch branch (range = the four commits above)
bun run build                              # rebuild dist/index.js
# then re-apply the dist-level patches (omo--durable-log-path, omo--fallback-toast-origin,
# omo--auto-slash-command-duplicate-user-args, omo--lookat-fallback-patience,
# omo--config-loader-transient-miss-guard) per their own reapply instructions —
# this rebuild clobbers them.
bash /home/ezotoff/ez-omo-config/scripts/verify-live-patches.sh
```

## Durable Alternative

An upstream mechanism for task-attempt in-place model switching (background-agent manager consulting the agent's `fallback_models` natively), terminal-only parent notification, and quota-terminal error classification in `oh-my-openagent` would eliminate this patch entirely. The pieces are additive and independently upstreamable.

Status: not-yet-pursued — candidate for upstream PRs against `code-yeongyu/oh-my-openagent`.
