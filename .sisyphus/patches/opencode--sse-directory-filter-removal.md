---
patch_id: "opencode--sse-directory-filter-removal"
dependency: "opencode"
target_file: "opencode"
target_install_path: "/home/ezotoff/src/opencode"
status: "active"
applied_date: "2026-06-26"
dep_version: "1.17.9-local"
upstream_issue: "https://github.com/anomalyco/opencode/pull/35913"
verification_pattern: "location\?\.workspaceID===void 0\|\|"
runtime_effective: false
runtime_effective_note: "NOT DEPRECATED (investigation 2026-08-06). workspaceID system exists in schema (Location.Ref.workspaceID: optional) but is NEVER POPULATED — 0 of 2107 live sessions have workspace_id set. Every Location.Ref.make() call passes only { directory }. Therefore the SSE ternary's workspaceID branch is never taken; ALL events fall through to directory check. The original worktree-events problem PERSISTS on v1.18.5. The patch is still needed but must be reimplemented for the rewritten event.ts (Effect/Stream migration)."

---

# OpenCode SSE event stream directory filter removal

## Problem
The SSE event handler in `event.ts` filtered events by `event.location?.directory === instance.directory`. This prevented worktree-based sessions from receiving events from their own workspace because the `directory` field in event locations does not always match the instance's configured directory (e.g., when running inside a worktree with a different path). Sessions in worktrees would miss real-time updates — tool completions, message parts, permission prompts — breaking the TUI's live-render for worktree development.

## Patch Description
Removed the `directory === instance.directory` condition from the `Stream.filter` in `eventResponse()`. The workspaceID filter is retained. Also added `?.` to the `workspaceID` access for null-safety since the directory guard that previously implied `location` is defined is gone.

Before:
```typescript
event.location?.directory === instance.directory &&
(event.location.workspaceID === undefined || event.location.workspaceID === workspaceID),
```
After:
```typescript
event.location?.workspaceID === undefined || event.location.workspaceID === workspaceID,
```

Committed as `c73249fe1` on branch `fix/sse-directory-filter-v1.17.9`.

## Verification
```bash
# The post-fix line uses ?. on workspaceID (the pre-fix version did not)
grep -n "location?\.workspaceID === undefined || event.location.workspaceID" \
  /home/ezotoff/src/opencode/packages/opencode/src/server/routes/instance/httpapi/handlers/event.ts

# Confirm the removed directory filter is absent
! grep -q "directory === instance.directory" \
  /home/ezotoff/src/opencode/packages/opencode/src/server/routes/instance/httpapi/handlers/event.ts
```

Binary verification (built binary contains the fix):
```bash
# The worktreeID concept (which the directory filter relied on) should be absent
grep -a -c "worktreeID" ~/.opencode/bin/opencode  # expect 0
```

## Deprecation Investigation (2026-08-06)

**Verdict: NOT DEPRECATED — patch still needed, needs v1.18.5 reimplementation.**

Investigated whether the v1.18.5 upstream SSE filter rewrite resolves the original worktree-events problem. Findings:

1. **New upstream code** (`event.ts`): uses a ternary `workspaceID !== undefined ? workspaceID match : directory fallback` instead of the old conjunction `directory match && (workspaceID match)`.
2. **workspaceID is never populated**: the `Location.Ref` schema has `workspaceID: optional(WorkspaceID)`, but every `Location.Ref.make()` call passes only `{ directory }`. The `WorkspaceContext` (AsyncLocalStorage) is not set during normal session/event creation.
3. **Empirical evidence**: `SELECT COUNT(*) FROM session WHERE workspace_id IS NOT NULL` returns 0 out of 2107 sessions.
4. **Consequence**: the SSE ternary's `workspaceID !== undefined` branch is NEVER taken. All events evaluate to `event.location?.directory === instance.directory` — the original buggy filter. Worktree sessions with a directory mismatch still miss events.
5. **Root cause persists**: in the `opencode serve` model, the server publishes events with `serviceLocation.directory` (the server's project directory), but a TUI client connected from a worktree has `instance.directory` set to the worktree path. The mismatch filters out the client's own events.

The workspaceID system was intended to solve this but is not wired up in v1.18.5. The patch must be reimplemented for the new `event.ts` structure.

## Reapply Instructions
### v1.18.5+ (Effect/Stream migration)

The `event.ts` file was completely rewritten for the Effect/Stream architecture. The old instructions do not apply.

1. Open `packages/opencode/src/server/routes/instance/httpapi/handlers/event.ts`.
2. In `eventResponse()`, find the `Stream.filter` callback (around line 36-39):
   ```typescript
   Stream.filter(
     (event) =>
       event.location?.workspaceID !== undefined
         ? event.location.workspaceID === workspaceID
         : event.location?.directory === instance.directory,
   ),
   ```
3. Remove the directory fallback. Replace the entire filter predicate with:
   ```typescript
   Stream.filter(
     (event) =>
       event.location?.workspaceID === undefined ||
       event.location.workspaceID === workspaceID,
   ),
   ```
   This accepts events with no workspaceID (the common case — workspaceID is never populated in v1.18.5) AND events with matching workspaceID. Only events with a DIFFERENT workspaceID are filtered.
4. Rebuild: `cd packages/opencode && OPENCODE_VERSION="$(~/.opencode/bin/opencode --version)" PATH=~/.bun/bin:$PATH ~/.bun/bin/bun run script/build.ts --single --skip-install --skip-embed-web-ui`.
5. Back up `~/.opencode/bin/opencode`, atomically replace with `packages/opencode/dist/opencode-linux-x64/bin/opencode`, restart `omo-tg.service` and `opencode.service`.
6. Verify: start a worktree session, trigger a tool call, confirm the TUI receives the event in real-time (no missed renders).

## Durable Alternative
Upstream PR to opencode removing the directory filter for worktree sessions. The fix is small and general — worktree-based development is a first-class opencode feature and the directory filter breaks it.
Status: not-yet-pursued
