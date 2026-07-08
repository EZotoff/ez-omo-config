---
patch_id: "opencode--sse-directory-filter-removal"
dependency: "opencode"
target_file: "packages/opencode/src/server/routes/instance/httpapi/handlers/event.ts"
target_install_path: "/home/ezotoff/src/opencode"
status: "active"
applied_date: "2026-06-26"
dep_version: "1.17.9-local"
upstream_issue: "https://github.com/anomalyco/opencode/pull/35913"
verification_pattern: "location\\?\\.workspaceID === undefined \\|\\| event\\.location\\.workspaceID"
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

## Reapply Instructions
1. Open `/home/ezotoff/src/opencode/packages/opencode/src/server/routes/instance/httpapi/handlers/event.ts`.
2. In `eventResponse()`, find the `Stream.filter` callback.
3. Remove the line: `event.location?.directory === instance.directory &&`.
4. Change `(event.location.workspaceID === undefined` to `event.location?.workspaceID === undefined` (remove opening paren, add `?.`).
5. Remove the closing `)` after `workspaceID)` on the same line.
6. Rebuild: `cd /home/ezotoff/src/opencode/packages/opencode && OPENCODE_VERSION="$(/home/ezotoff/.opencode/bin/opencode --version)" PATH=/home/ezotoff/.bun/bin:$PATH /home/ezotoff/.bun/bin/bun run script/build.ts --single --skip-install --skip-embed-web-ui`.
7. Back up `~/.opencode/bin/opencode`, atomically replace with `packages/opencode/dist/opencode-linux-x64/bin/opencode`, restart `omo-tg.service` and `opencode.service`.

## Durable Alternative
Upstream PR to opencode removing the directory filter for worktree sessions. The fix is small and general — worktree-based development is a first-class opencode feature and the directory filter breaks it.
Status: not-yet-pursued
