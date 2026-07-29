---
patch_id: "omo--runtime-fallback-checktoolstate-bypass"
dependency: "oh-my-openagent"
target_file: "dist/index.js, packages/omo-opencode/src/hooks/runtime-fallback/auto-retry-dispatch.ts"
target_install_path: "/home/ezotoff/oh-my-openagent-v4.12.1"
status: "active"
applied_date: "2026-07-25"
dep_version: "4.12.1"
upstream_issue: "https://github.com/code-yeongyu/oh-my-openagent/pull/5357"
verification_pattern: "checkToolState: false"
---

# OMO runtime-fallback checkToolState bypass (fork port, hardened)

## Problem

When `runtime_fallback.enabled = true`, provider quota/usage errors fire the
`session.status` retry path: it aborts the dead stream, shows the "Switching to
<model>" toast, and calls `autoRetryWithFallback`. The dead assistant turn (aborted
or errored) never receives a completion marker, so the prompt-async gate's
`checkToolState` (`sessionLatestAssistantBlocksInternalPrompt`) returns
`{ status: "active" }` forever. The fallback continuation is silently dropped:
toast shown, session permanently halted, and the prompt queue drain spams
`promptAsync skipped because latest assistant is still active`. Reported 2026-07-25
(ses_0af001ee5ffe2GbfIKxDB0z1v5; loop evidence on ses_06f5f83e2ffe6NPbh4YxKu8S2k).

## History

- **2026-07-15 (4.3.1 era):** first applied as a direct edit to the npm-cached
  `~/.cache/opencode/node_modules/oh-my-openagent/dist/index.js`, conditional on
  `deps.internallyAbortedSessions.has(sessionID)` (upstream PR #5357 shape).
  Verified live the same day.
- **2026-07-23:** live config switched to the local fork
  `file:///home/ezotoff/oh-my-openagent-v4.12.1` (commit `1b9c6cb`). The npm-cache
  edit was stranded; the fork never had the fix. This patch file existed only in
  `.omo/patches/`, outside the verifier's `.sisyphus/patches/` scope, so the loss
  was silent.
- **2026-07-25 (first port, 8ccab70):** ported the upstream conditional check into
  fork source. Live verification showed it was INSUFFICIENT on 4.12.1: the
  `session.error` abort event consumes `internallyAbortedSessions` (issue #4006
  handling, added after 4.3.1) before the dispatch reads it, and the
  `session.error` dispatch path never sets the flag at all.
- **2026-07-25 (hardened, 1c76421):** bypass made unconditional at the
  runtime-fallback dispatch call site. Registered in `.sisyphus/patches/`.

## Patch Description

In `packages/omo-opencode/src/hooks/runtime-fallback/auto-retry-dispatch.ts`, the
`dispatchRetryPrompt` closure inside `createAutoRetryDispatcher` passes
`checkToolState: false` on every `dispatchInternalPrompt` call (initial defer,
active-queue retry, reserved-retry loop, and queue-drain entries).

Rationale for unconditional (vs upstream's conditional): every runtime-fallback
dispatch targets a session whose stream just died — either aborted by the
session.status path or terminal-errored in the session.error path. The gate's
`isSessionActive` status check (session-idle-dispatch.ts) remains as the real
liveness guard; the tool-state check only observes the dead turn's missing
completion marker and can never pass. Other (non-fallback) gate callers keep the
tool-state check unchanged.

## Verification

```bash
# Source-level verification (must match in BOTH dist/index.js and source .ts)
grep -c "checkToolState: false" \
  /home/ezotoff/oh-my-openagent-v4.19.2/dist/index.js \
  /home/ezotoff/oh-my-openagent-v4.19.2/packages/omo-opencode/src/hooks/runtime-fallback/auto-retry-dispatch.ts
# Expected: >= 1 in each file (verifier requires ALL targets to match)

# Full verifier run
bash scripts/verify-live-patches.sh
# Expected: APPLIED for omo--runtime-fallback-checktoolstate-bypass
```

Live behavior verification: after server restart, watch
`/tmp/oh-my-opencode.log` for `runtime-fallback:` sources — fallback dispatches
should log `promptAsync dispatched` (or `queued` then dispatched) instead of the
repeating `skipped because latest assistant is still active` loop. A sync
sub-agent on a quota-limited provider should continue on its fallback model after
the toast instead of halting.

## Reapply Instructions

1. In the fork source
   `packages/omo-opencode/src/hooks/runtime-fallback/auto-retry-dispatch.ts`,
   add `checkToolState: false,` to the `dispatchInternalPrompt` argument object
   in the `dispatchRetryPrompt` closure.
2. `bunx tsgo --noEmit -p packages/omo-opencode/tsconfig.json` (typecheck).
3. Rebuild: `bun build packages/omo-opencode/src/index.ts --outdir dist --target bun --format esm --external zod`.
4. Confirm the verification regex above matches `dist/index.js`.
5. Restart: `systemctl --user restart opencode.service omo-tg.service`.

## Durable Alternative

Upstream PR #5357 (merged 2026-07-08) contains the real fix; it first shipped in
OMO v4.18.1. Upgrading the runtime from the local v4.12.1 fork to >= v4.18.1 makes
this patch unnecessary. The 4.12→4.18 migration is being prepared separately in
the omo-hub project. NOTE: if v4.18.1's implementation is also conditional on
`internallyAbortedSessions`, re-verify it does not hit the same flag-consumption
race before deprecating this patch.
Status: pursued
