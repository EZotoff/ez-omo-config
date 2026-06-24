---
patch_id: "omo--parent-wake-sync-mode-for-tui-render"
dependency: "oh-my-openagent"
target_file: "dist/index.js (sendParentWakePrompt function, ~line 119744)"
target_install_path: "/home/ezotoff/oh-my-openagent-v4.12.1"
status: "active"
applied_date: "2026-06-24"
dep_version: "4.12.1"
upstream_issue: "https://github.com/code-yeongyu/oh-my-openagent/issues/5189"
verification_pattern: 'forceNoReply !== true && input.latestWake.shouldReply ? "sync"'
post_update_status: "reapply_required"
note: "Fixes invisible-message bug: assistant responses to background-task-completion parent-wake continuations are persisted but not live-rendered in the TUI because OpenCode's promptAsync path doesn't reliably deliver message.part.delta SSE events to an already-open TUI. Switching to sync session.prompt() for shouldReply wakes routes through the TUI's normal message stream. noReply (informational) wakes remain async."
---

# Parent-Wake Sync Mode for TUI Live-Render

## Problem

When a background sub-agent completes, OMO injects a `<system-reminder>` continuation into the parent session via `session.promptAsync()`. OpenCode persists the continuation user message and the resulting assistant response to the session database, but the already-open TUI's SSE stream does not reliably deliver `message.part.delta` events for externally-injected turns.

**Symptom**: The user sees the "waiting for Oracle/sub-agent" message, then the "Oracle is done" notification, then the agent's short acknowledgement — but the full root-cause analysis message produced between those two events is invisible in the live TUI. Forking or re-reading the session reveals the missing message was persisted correctly.

**Root cause**: OpenCode's `promptAsync` endpoint accepts and persists messages but the TUI's SSE event subscription does not reliably stream `message.part.delta` for turns initiated externally (not by user typing in the TUI). This is upstream OpenCode behavior (issues #26671, #27380, #32010 on the public tracker).

## Patch Description

In `sendParentWakePrompt()` at `dist/index.js:119744`, changed the `dispatchInternalPrompt` mode from unconditional `"async"` to conditional:

```js
// BEFORE:
mode: "async",

// AFTER:
mode: input.forceNoReply !== true && input.latestWake.shouldReply ? "sync" : "async",
```

**Why conditional**: Only `shouldReply` wakes (where the agent is expected to produce a visible assistant turn) need sync mode. `noReply` wakes (informational reminders with `forceNoReply: true` or `shouldReply: false`) don't produce visible assistant output, so they can stay async — sync mode would block the event loop unnecessarily.

**What sync mode does**: `session.prompt()` is a blocking call that goes through OpenCode's normal message stream — the same SSE event path the TUI subscribes to for user-typed messages. The TUI receives `message.part.delta` events and live-renders the assistant response.

**Safety**: `dispatchInternalPrompt` with `mode: "sync"` uses `queueBehavior: "defer"` (already set), which waits for the session to be idle before dispatching. The function is already `async`/`await`-based, so the blocking happens in the async context without freezing the event loop.

## Verification

```bash
# Verify the patch is present
grep -c 'forceNoReply !== true && input.latestWake.shouldReply ? "sync"' \
  /home/ezotoff/oh-my-openagent-v4.12.1/dist/index.js
# Expected: 1

# Verify syntax is valid
node --check /home/ezotoff/oh-my-openagent-v4.12.1/dist/index.js
# Expected: no errors

# Verify other dispatch sites are untouched (should still have ~13 mode: "async")
grep -c 'mode: "async"' /home/ezotoff/oh-my-openagent-v4.12.1/dist/index.js
# Expected: 13
```

### Runtime QA

After restarting OpenCode:
1. Launch a background sub-agent (e.g., `task(subagent_type="explore", run_in_background=true, ...)`)
2. End the parent turn
3. Wait for the background task completion notification
4. The parent agent should auto-continue and the assistant response should be **visible in the live TUI** (not just persisted)

If the response is still invisible after this patch, the issue is deeper in OpenCode's SSE event delivery for sync prompts dispatched from plugin context, and upstream reporting is needed.

## Reapply Instructions

If the patch is lost after an OMO update:

1. Find `sendParentWakePrompt` in the new `dist/index.js`:
   ```bash
   grep -n 'sendParentWakePrompt' /home/ezotoff/oh-my-openagent-v4.12.1/dist/index.js
   ```

2. In the `sendParentWakePrompt` function body, find the `dispatchInternalPrompt` call with `mode: "async"` and `source: "background-agent-parent-wake"`.

3. Change:
   ```js
   mode: "async",
   ```
   to:
   ```js
   mode: input.forceNoReply !== true && input.latestWake.shouldReply ? "sync" : "async",
   ```

4. Verify syntax:
   ```bash
   node --check /home/ezotoff/oh-my-openagent-v4.12.1/dist/index.js
   ```

5. Restart OpenCode.

## Durable Alternative

Upstream OMO could:
- Detect TUI mode at runtime and choose sync/async dispatch automatically
- Or add a post-dispatch TUI session-refresh call after `promptAsync` to force the TUI to backfill from REST

Upstream OpenCode could:
- Fix the SSE event delivery for `promptAsync`-initiated turns so `message.part.delta` events are reliably streamed to all connected TUI clients
- Add a session-refresh mechanism that the TUI calls after reconnect or after detecting externally-injected messages

Status: upstream issues exist but are unresolved. This local patch is the bridge until they ship.

## Related Issues

- OMO #5189 — Parent wake sent with forceNoReply=true, agent never auto-responds
- OMO #5172 — prompt-async-gate deadlock
- OMO #4874 — all-complete parent wake consumed as noReply before session resume
- OMO PR #5488 — requeue silent parent wake (merged, partially addresses related edge case)
- OpenCode #26671 — TUI does not live-render messages when prompt is POSTed externally via prompt_async
- OpenCode #27380 — TUI session messages stay stale after reconnect
