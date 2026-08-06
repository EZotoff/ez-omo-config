---
patch_id: "opencode--tui-pinned-session-race"
dependency: "opencode"
target_file: "packages/tui/src/context/local.tsx"
target_install_path: "/home/ezotoff/.opencode/bin/opencode"
source_repo: "/home/ezotoff/src/opencode"
status: "active"
applied_date: "2026-08-06"
dep_version: "1.18.5"
runtime_effective: false
runtime_effective_note: "Unfixed upstream bug. The race condition exists in the live v1.18.5 binary. No patch applied yet — this entry tracks the bug for resolution."
upstream_issue: "none"
verification_pattern: "pinned"
surfaces: "tui-interactive"
---

# OpenCode TUI pinned-session reset (upstream race condition)

## Problem

Pinned sessions in the TUI intermittently reset to an older state. The pin feature was introduced in commit `12583b18f feat(tui): pin, quick-switch, and cycle recent sessions` (2026-07-24) and first shipped in the v1.18.5 line. It did NOT exist in v1.17.9 — the bug is new to v1.18.x, not a regression from the v1.17.9→v1.18.5 upgrade.

## Root Cause

Pins are stored in a single JSON file: `~/.local/state/opencode/session.json` (`path.join(paths.state, "session.json")`). The TUI reads it once at startup and writes it on every pin toggle and on every `session.deleted` event (via `prune()`). There is no file locking and no last-writer-wins detection.

Two race conditions in [`packages/tui/src/context/local.tsx`](file:///home/ezotoff/src/opencode/packages/tui/src/context/local.tsx) lines 411-501:

### Race 1: Startup read-overwrite (lines 436-450)

```typescript
readJson<unknown>(filePath)
  .then((x) => {
    // ... setSessionStore("pinned", x.pinned) — OVERWRITES in-memory state
  })
  .finally(() => {
    setSessionStore("ready", true)
    if (state.pending) save()  // writes file content back to disk
  })
```

If the user toggles a pin BEFORE `readJson` resolves:
1. `togglePin` modifies in-memory `pinned`, calls `save()` → `state.pending = true` (deferred).
2. `readJson` resolves → `.then()` overwrites in-memory `pinned` with the file's older content.
3. `.finally()` fires `save()` → writes the older content back to disk.

**Result**: the user's pin is wiped from both memory and disk. The window is the `Bun.file(...).json()` duration (1-10 ms on warm cache), reachable in normal use via the session-switcher keybind.

### Race 2: Multi-process file contention

Each TUI process loads `session.json` into its own in-memory `pinned` array at startup and writes the full array on every `prune()` call (triggered by `session.deleted` events). With multiple TUI processes running simultaneously, the oldest process's stale in-memory array overwrites newer pins from other processes whenever a session is deleted.

**Observed state**: 5 simultaneous `opencode` TUI processes, oldest alive 19+ hours. The oldest process's pin list (loaded 19h ago) overwrites newer pins whenever any `session.deleted` event fires.

## User-Visible Symptom

Pinned sessions in the TUI session switcher revert to an older set after some time (especially after session cleanup/archive events trigger `prune()` in a long-running TUI instance).

## Proposed Fix

Two changes in `local.tsx`:

1. **Guard the startup read against in-memory mutations**: in the `.then()` callback, check `state.pending` before overwriting. If `pending` is true (a mutation occurred before the read resolved), merge the file content with the in-memory state instead of replacing it.

2. **Add advisory file locking** around `readJson` + `writeJsonAtomic` using `flock(2)` or `proper-lockfile`, so concurrent TUI processes cannot race on read-modify-write.

## Runtime Verification

1. Start `opencode` (interactive TUI).
2. Pin a session via the session-list keybind (`Ctrl+F` → navigate → `session.pin.toggle`).
3. Check `~/.local/state/opencode/session.json` — the pinned session ID should appear in the `pinned` array.
4. Wait 30 seconds (or trigger a session.deleted event by deleting another session).
5. Re-open the session list — the pinned session should still be at the top.
6. **Regression signal**: pinned session disappears from the list, or `session.json` reverts to an older `pinned` array.

For multi-process verification:
1. Start two `opencode` TUI instances.
2. Pin session A in instance 1.
3. Pin session B in instance 2.
4. Trigger a `session.deleted` event (delete a third session).
5. **Regression signal**: either pin A or pin B disappears (the process that handles the delete event overwrites the other's pin).

## Workaround

Close all but one `opencode` TUI process. Pin via the keybind only after the TUI has been running for >1 second (so the initial `readJson` has resolved). The file content will not be reset until another TUI process fires `prune()`.

## Reapply Instructions

This is an upstream bug, not a local patch. The fix should be submitted upstream to `sst/opencode` or applied locally via the `patch-opencode` skill once the fix is written.

When patching:
1. Identify the ACTIVE rendering hook point in the TARGET version — the `createSession()` function in `packages/tui/src/context/local.tsx`.
2. Add the `state.pending` guard in the `readJson().then()` callback.
3. Add `flock` or equivalent around the read-modify-write cycle.
4. Build from `v1.18.5` tag with `OPENCODE_VERSION=$(~/.opencode/bin/opencode --version) bun run script/build.ts --single --skip-install --skip-embed-web-ui`.
5. Verify the fix using the Runtime Verification steps above on both single-process and multi-process scenarios.
