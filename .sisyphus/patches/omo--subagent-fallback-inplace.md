---
patch_id: "omo--subagent-fallback-inplace"
dependency: "oh-my-openagent"
target_file: "packages/omo-opencode/src/features/background-agent/fallback-retry-handler.ts, packages/omo-opencode/src/features/background-agent/background-task-notification-template.ts, packages/omo-opencode/src/features/background-agent/manager.ts, packages/omo-opencode/src/features/background-agent/manager.test.ts, packages/omo-opencode/src/features/background-agent/fallback-retry-handler.test.ts"
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

Full todos-1-4 diff touches 15 files (10 more without the marker: attempt-lifecycle.ts, error-classifier.ts, atlas-subagent-fallback-retry.test.ts, claude-code-session-state/state.ts, hooks/runtime-fallback/{fallback-retry-dispatcher.ts,fallback-retry-dispatcher.test.ts,message-update-handler.ts,subagent-quota-abort.test.ts}, model-core/{runtime-fallback-error-classifier.ts,model-error-classifier.test.ts}); target_file lists the 5 marker-bearing discriminative files because verify-live-patches.sh requires ALL target_file entries to match verification_pattern.

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

## Runtime Status

**2026-10-05 16:08:39-16:12:14 CEST: BLOCKED; runtime_effective remains false.**
One initial observation and exactly ONE diagnostic retry were performed. Neither
reached the fixture provider, so neither proves an in-place fallback. No third
attempt, provider substitution, global config edit, or service restart was made.

- Existing live server: `http://127.0.0.1:3021`, PID 3031462, started
  2026-10-05 16:03:45 CEST; interactive server PID 3038428 started 16:03:59.
  OpenCode version unchanged: `1.18.31-p3`. Active config references
  `../../oh-my-openagent-v4.19.2`; scratch instance plugin-entry log at
  `2026-10-05T14:08:50.694Z` confirms OMO loaded on the live server. Bundle
  timestamp: 2026-10-05 11:39:32 CEST, size 5647006 bytes.
- Forced failure: exact plan HTTP fixture at `127.0.0.1:18270` (port registered
  through deployment workflow), returning HTTP 401 with
  `{"error":{"message":"you (fixture) have reached your weekly usage limit, upgrade for higher limits: https://example.com"},"code":"provider_usage_limit"}`.
  `curl -X POST .../v1/chat/completions` returned **401**. Provider config was
  scratch-local `.opencode/opencode.json`, exactly the plan's provider-only block.
- CLI observation used the plan prompt plus `--attach http://127.0.0.1:3021`
  to exercise the existing post-restart server rather than start a new server.
  Parent: `ses_ef39aa6f0ffeVk4bomq6hhq83e` (created 14:08:50 UTC).
  Initial task `bg_ca4334db`, child `ses_ef39a17eeffeICTUyTxDoXp4N0`
  (14:09:27 UTC); diagnostic retry `bg_245d12b6`, child
  `ses_ef398e556ffe1vtYegHobJMEsV` (14:10:46 UTC). Both replied `OK`
  on **ollama-cloud/minimax-m3**, not fixture-provider/quota-test-model.
- Transcript excerpt: "`model` is not a supported parameter of task() ...
  this retry also ran on the explore agent's default model. The
  fixture-provider/quota-test-model endpoint remains unexercised by both probes."
  Read-only DB task metadata independently confirms both default-model launches;
  persisted inputs have no `model`. Source `delegate-task/tools.ts:61-79`
  defines no model argument. This is the fixture's blocking assumption, not
  evidence that the fallback implementation failed.
- Assertions: zero per-hop retry-wake strings; zero `fell back` summaries;
  zero durable-log `EZ-PATCH: subagent-fallback-inplace` lines. No across-hop
  child-session stability proof is possible because no hop happened.
  The live `configs/` git status remained empty.
- `bash scripts/verify-live-patches.sh`: this entry **APPLIED**; overall exit 1
  due to unrelated existing STALE entries (gpt6-hephaestus-registration,
  task-hygiene-close-before-turn-end, wake-journal-outbox,
  tui-error-toast-directory-scope) and a worktree-relative MISSING-TARGET
  (start-work-worktree-teardown). No unrelated repairs attempted.
- Cleanup receipt at 16:12:14 CEST: `systemctl --user stop omo-fixture-obs`;
  `MainPID=0`, `LoadState=not-found`, `ActiveState=inactive`; no port-18270
  listener. Temporary port reservation released after cleanup.
- Durable evidence: `/home/ezotoff/ez-omo-config/.omo/evidence/subagent-fallback-rework/task-8-observation.log`
  (parent transcript, commands, model/session metadata, log excerpts, cleanup).

**Next required decision:** correct the plan's model-selection seam (for example,
an explicitly approved scratch-local OMO agent override) before a new observation.
No alternate seam was silently substituted. Not verified live: in-place fallback
handler invocation and real-project fallback behavior.

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
