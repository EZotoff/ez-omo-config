---
patch_id: "omo--ultrawork-subagent-guard"
dependency: "oh-my-openagent"
target_file: "packages/omo-opencode/src/plugin/system-transform.ts, packages/omo-opencode/src/plugin-interface.ts, packages/omo-opencode/src/plugin/system-transform-subagent-guard.test.ts"
target_install_path: "/home/ezotoff/oh-my-openagent-v4.19.2"
status: "active"
applied_date: "2026-09-06"
dep_version: "4.19.2"
upstream_issue: "none"
verification_pattern: "isSubagentSession"
runtime_effective: false
note: "Source patch, committed in the fork as 52a175587 (guard + tests) and 753602683 (plugin-interface wiring) on branch fix/custom-patches-v4.19.2, embedded in dist/index.js via the 2026-09-06 rebuild. Behavioral patch (server plugin handler), not a rendering/monkey patch — pattern-presence in the bundle plus unit tests carry the structural guarantee; the live subagent-observation check below flips runtime_effective."
---

# Ultrawork Default-Mode Injection Skips Subagent Sessions

## Problem

OMO v4.19.2's `experimental.chat.system.transform` handler (`packages/omo-opencode/src/plugin/system-transform.ts:20-30`) injects the ultrawork system-prompt bundle into **every** session whenever `default_mode.ultrawork: true` — no session-type filtering whatsoever. task()-spawned child sessions (subagents, category executors, background tasks) therefore receive the full ultrawork mandate, which:

- forces the "ULTRAWORK MODE ENABLED!" announcement as the child's first output (the injected bundle mandates it, `packages/prompts-core/prompts/ultrawork/default.md:3`) — measured on ez-omo-bench subjects 2026-09-01: 26/28 bench subject sessions announced;
- caused a document-writer bench subject to announce, then end its turn without doing the task (headless `opencode run` has no human to continue) — a 0.0 bench score caused purely by this injection (evidence: `ez-omo-bench/.sisyphus/research/run-notes-20260831-phase3.md` § Forensic pass);
- loads subagents with TDD/code-mode mandates irrelevant to their task (token + behavior noise; delegation-latency decomposition attributed ~59% of delegated wall-clock to child agent-prompt effect — explore ses_f8937668fffe7wCLsWQDgknjAv).

OMO already contains the correct main-session-only semantics in TWO places (`src/hooks/keyword-detector/hook.ts:108-117`: `subagentSessions.has(...)` skip + `getMainSessionID()` → non-main skip; and the default-mode branch at ~118 guarded by `!isNonMainSession`) — the system-transform path simply lacked the guard.

## Patch Description

**Files changed (3):** source patch in the fork (commits 52a175587 + 753602683), rebuilt into `dist/index.js` on 2026-09-06.

1. `plugin/system-transform.ts` — new exported interface `SystemTransformSessionState { isSubagentSession(sessionID): boolean; getMainSessionID(): string | undefined }` passed as an **optional third parameter** to `createSystemTransformHandler` (undefined → legacy behavior, handler stays unit-testable). In the default-mode branch, after the `!defaultMode?.ultrawork || !getUltraworkMessage` early return and BEFORE the `<ultrawork-mode>` dedupe check, the guard mirrors keyword-detector hook.ts:108-117:
   ```ts
   if (sessionState && input.sessionID) {
     if (sessionState.isSubagentSession(input.sessionID)) return
     const mainSessionID = sessionState.getMainSessionID()
     if (mainSessionID && input.sessionID !== mainSessionID) return
   }
   ```
   `reconcileSisyphusRuntimePrompt` (issue #5297) runs unconditionally BEFORE the guard — model-family prompt reconciliation keeps firing for all sessions, only the ultrawork injection is gated. When `getMainSessionID()` is undefined (no main session registered yet, e.g. headless `opencode run`), the non-main guard passes through — fail-open toward injection, preserving the operator requirement that main sessions keep ultrawork.
2. `plugin-interface.ts` — the `"experimental.chat.system.transform"` wiring now passes a session-state adapter built from the shared singletons (`features/claude-code-session-state`): `{ isSubagentSession: (sid) => subagentSessions.has(sid), getMainSessionID }`. These are the exact same module-level singletons the keyword-detector hook consumes — no new state, no accessor threading through createHooks.
3. `system-transform-subagent-guard.test.ts` — four Given/When/Then tests: main session + default → injected (regression lock for the operator requirement); registered subagent session → NOT injected; non-main session (≠ registered main) → NOT injected; deps undefined → injected (legacy backward-compat lock; also the exact configuration used by the pre-existing `default-mode-priority.test.ts`, which therefore doubles as an unmodified legacy-path proof).

Config unchanged: `default_mode.ultrawork: true` stays global (operator requirement, verbatim: "I still want the main sessions to run as ultra work by default").

## Verification

```bash
# Source (necessary and sufficient for a source patch):
grep -c 'isSubagentSession' /home/ezotoff/oh-my-openagent-v4.19.2/packages/omo-opencode/src/plugin/system-transform.ts   # >= 2
# Wiring:
grep -c 'subagentSessions.has' /home/ezotoff/oh-my-openagent-v4.19.2/packages/omo-opencode/src/plugin-interface.ts         # >= 1
# Tests (4 guard tests + 10 pre-existing handler tests, no regressions):
cd /home/ezotoff/oh-my-openagent-v4.19.2 && bun test packages/omo-opencode/src/plugin/system-transform-subagent-guard.test.ts packages/omo-opencode/src/plugin/default-mode-priority.test.ts packages/omo-opencode/src/plugin/sisyphus-runtime-prompt-reconciler.test.ts   # 14 pass
# Bundle (embedded via rebuild):
grep -c 'isSubagentSession' /home/ezotoff/oh-my-openagent-v4.19.2/dist/index.js   # >= 2
```

## Runtime Verification

Behavioral patch; the sufficient check is observing session-type discrimination on the live surface:

1. After `systemctl --user restart opencode.service` (omo-tg.service is masked/retired — verify unit state before including it), confirm server start time changed (`ps -eo pid,lstart,etime,args | grep 'opencode serve'`).
2. From a NEW main session: the session still announces "ULTRAWORK MODE ENABLED!" on its first turn (operator requirement holds).
3. Spawn a task() subagent from that session; export/inspect the child session's messages — must contain ZERO occurrences of `ULTRAWORK` (no announcement, no injected bundle).
4. Optional cross-check: ez-omo-bench's interim mitigation (`default_mode: {ultrawork: false}` per bench workspace) becomes a harmless no-op — bench behavior unchanged.
5. Flip `runtime_effective: true` and record the observation timestamp in a `## Runtime Status` section when steps 2-3 pass.

**Regression signal:** if a NEW main session stops announcing ultrawork, the non-main guard is over-matching (e.g. main session not registered via `event-session-lifecycle.ts:69` before the first transform fires) — set `runtime_effective: false`, add `## Runtime Status` documenting it, do NOT bump `dep_version`.

## Reapply Instructions

Source patch — reapply from fork commits 52a175587 + 753602683 (branch `fix/custom-patches-v4.19.2`):

```bash
cd /home/ezotoff/oh-my-openagent-v4.19.2
git show 52a175587 --stat && git show 753602683 --stat   # 3 files listed
git cherry-pick 52a175587 753602683                      # on the next-version patch branch
bun run build                                             # rebuild dist/index.js
# then re-apply the four dist-level patches (omo--durable-log-path,
# omo--fallback-toast-origin, omo--lookat-fallback-patience,
# omo--auto-slash-command-duplicate-user-args) per their own reapply
# instructions — this rebuild clobbers them.
bash /home/ezotoff/ez-omo-config/scripts/verify-live-patches.sh
```

The guard is the block starting `if (sessionState && input.sessionID) {` in `system-transform.ts`, placed after the `!defaultMode?.ultrawork || !getUltraworkMessage` early return; on a future upstream refactor, re-place it so `reconcileSisyphusRuntimePrompt` still runs unconditionally before any guard.

## Durable Alternative

Upstream fix in `code-yeongyu/oh-my-openagent`: the guard mirrors the maintainer's own keyword-path logic (hook.ts:108-117) — strong precedent. Filing an issue + PR (default-mode system.transform injection should skip subagent/non-main sessions exactly like the keyword-detector default-mode branch) would let this patch be marked `upstreamed`.

Status: not-yet-pursued — candidate for an upstream PR against `code-yeongyu/oh-my-openagent`.
