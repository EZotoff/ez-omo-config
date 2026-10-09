---
patch_id: "opencode--sse-directory-filter-removal"
dependency: "opencode"
target_file: "packages/opencode/src/server/routes/instance/httpapi/handlers/event.ts"
target_install_path: "/home/ezotoff/src/opencode/packages/opencode/src/server/routes/instance/httpapi/handlers/event.ts"
surfaces: "server-api"
verification_strength: "weak"
note: "lockfile required:true since 2026-09-30 (was acknowledged-drift before the 1.18.31-p2 re-apply)"
required_evidence: "runtime"
status: "active"
applied_date: "2026-06-26"
dep_version: "1.18.31-p4"
upstream_issue: "https://github.com/anomalyco/opencode/pull/35913"
verification_pattern: "location\\?\\.workspaceID===void 0\\|\\|"
runtime_effective: true
runtime_effective_note: "Verified live 2026-09-29 ~20:15 CEST on 1.18.31-p2 (build 3787fd6b): V2 — `curl -N /event?directory=<bench>` on 3030 delivered 84 KB of message.part/tool events in 8s including 19 events originating from OTHER directories (pre-fix: only server.connected); V4 — attach TUI in a git worktree received +35 KB of streamed events during a turn in its worktree. Base 48eedf9406 +2 commits, merged to fork/fix/v1.18.31-question-stall-watchdog @ 633fc201b9 (pushed)."
---

# OpenCode SSE event stream directory filter removal (v1.18.x Effect/Stream reimplementation)

## Problem
The instance `/event` route filtered events by `event.location?.directory === instance.directory`. Events are published with the originating instance's directory, so any subscriber attached to a different directory — worktree sessions, external observers (OMO supervisor, dashboards) — received nothing but `server.connected`. This starved external consumers and forced them into heavyweight HTTP transcript polling (measured 17.6 MiB/s of loopback from the supervisor's 20s full-transcript polls on 2026-09-29).

## Patch Description
In `eventResponse()`'s `Stream.filter`, drop the `event.location?.directory === instance.directory &&` conjunct; keep the workspaceID clause with `?.` null-safety. Broadcast semantics as on the v1.17.9-patched line.

After:
```typescript
Stream.filter(
  (event) =>
    event.location?.workspaceID === undefined || event.location.workspaceID === workspaceID,
),
```

## Runtime Verification
1. `curl -sN -u opencode:<pw> 'http://127.0.0.1:3030/event?directory=<dir-with-active-session>'` while a session streams → expect message.part/tool events including events from other directories.
2. Attach a TUI in a git worktree, run a turn from the main checkout → live-render updates (data-level: socket byte delta > 0 on the attach process).

## History
- v1.17.9 version removed the filter in the pre-Effect event.ts (commit c73249fe1, branch fix/sse-directory-filter-v1.17.9).
- 2026-08-06 investigation: upstream's workspaceID fix never populated (0/2107 sessions); patch still required, needed reimplementation for the rewritten event.ts.
- 2026-09-29: reimplemented on 1.18.31-p2, verified live (see runtime_effective_note).

## Notes
- The TUI's own route `/global/event` streams from GlobalBus (already unfiltered) — unaffected.
- The verification pattern is shared with the minified old form; the distinguishing signal is the ABSENT `directory === instance.directory` source text plus runtime evidence.
- Related upstream: issues #35917, #49861; fork PR #49963. No upstream fix through v2.0.11.
