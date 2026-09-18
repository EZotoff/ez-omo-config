---
patch_id: "opencode--tui-pinned-session-race"
dependency: "opencode"
target_file: "packages/tui/src/context/local.tsx"
target_install_path: "/home/ezotoff/.opencode/bin/opencode"
source_repo: "/home/ezotoff/src/opencode"
status: "active"
applied_date: "2026-08-15 (v1 races), 2026-08-26 (v2 togglePin RMW)"
dep_version: "1.18.5"
runtime_effective: false
runtime_effective_note: "v1 (merge guard + prune RMW, commit e7f5981ea, live since 2026-08-15 12:25): 11 days of pin-watch.log surveillance show zero startup-read or prune-path wipes — all corruption events since v1 are the togglePin path. v2 (togglePin file-level RMW, commit e31c20ca3, live since 2026-08-26): awaiting first post-swap togglePin write in pin-watch.log that preserves ids unknown to the writing process. Flip to true after that observation."
upstream_issue: "none"
verification_pattern: "pinned"
verification_strength: "weak"
required_evidence: "provenance"
verification_note: "Bun minification strips comments and renames locals; this patch contains no unique string literal or property key, so pattern-presence is a weak pre-filter only. Authority rests on the regression test (tests/regressions/012-pinned-session-race-fix.sh), source commit e7f5981ea, and the runtime_effective flag."
surfaces: "tui-interactive"
---

# OpenCode TUI pinned-session reset — FIXED locally 2026-08-15

## Problem (confirmed by surveillance)

Pinned sessions in the TUI session list lose their pin marks after reboots. Surveillance (inotify watcher on `~/.local/state/opencode/session.json`, 2026-08-15) captured the exact corruption event: a TUI process that started BEFORE a pin was added received a `session.deleted` event 71 minutes later and executed `prune()`, which called `save()` unconditionally — rewriting the whole file from its startup-era in-memory snapshot and wiping the newer pin. The reboot was never the cause; it only restarts all TUIs (zellij resurrects 4+ panes), which makes pre-existing corruption visible and multiplies concurrent stale writers.

## Root Cause

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

## Fix Applied (2026-08-15, source commit e7f5981ea)

Two changes in `createSession()` (`packages/tui/src/context/local.tsx`):

1. **Startup read merge guard** (Race 1): in the `readJson().then()` callback, if `state.pending` is true (a pin mutation occurred before the read resolved), merge the file's `pinned` array into memory instead of replacing it. The deferred `save()` then persists the union rather than the stale file content.
2. **prune() as file-level read-modify-write** (Race 2): `prune` no longer writes the in-memory snapshot. It reads the file's CURRENT content, removes only the deleted session id, and writes that back. A long-running TUI processing a deletion can no longer overwrite pins added by other processes since it started. The in-memory store is still updated (if it contained the id) so the local UI stays consistent.

**Residual risk** (documented, accepted): `togglePin` still writes the process-local in-memory array. Two TUIs toggling pins within each other's staleness window can still lose one another's toggles. The upstream-proper fix is advisory file locking (flock/proper-lockfile) around the read-modify-write cycle; this patch deliberately stays minimal and fixes the two proven corruption paths.

## Regression Test

`tests/regressions/012-pinned-session-race-fix.sh` (+ `.kill.sh`) asserts the two structural fix markers remain in the TUI source and that `prune()` never regains a `save()` call.

## Recurrence 2026-08-25 — Race 3: stale togglePin whole-array write (v2)

Surveillance (`.sisyphus/pin-watch.log`) captured the recurrence that v1 documented as residual risk:

- 17:55:18 — PID 18464 pins `ses_fe6b51ec4ffeCNm6lddCbq2abR` (ez-omo-bench, "Distributed GPU use") → 38 pins on disk.
- 19:35:44 — PID 18794, a TUI started BEFORE 17:55, pins an unrelated session → `togglePin` calls `save()` → writes its stale 37-pin startup-era array + its own toggle → **the 17:55 pin is wiped from disk**.
- 19:40:00 — PID 18794 unpins that session → 37 pins remain, the victim pin is gone.
- 23:22 — reboot. Post-boot TUIs read the corrupted file; the user sees the pin missing and re-pins at 00:06:21 (PID 74243).

The reboot was again only the messenger — corruption happened 3h47m earlier. v1 fixed the startup read and `prune` write paths but left `togglePin` writing the full process-local in-memory array.

### v2 Fix (2026-08-26, source commit e31c20ca3)

`togglePin` is now a file-level read-modify-write, mirroring the v1 `prune` fix: toggle direction comes from this TUI's in-memory view (preserving user intent as displayed), but the write mutates only the toggled id against the file's CURRENT content; every other id on disk is preserved. In-memory state is synced to the disk result. If the file is unreadable, the write falls back to the in-memory projection so the user's toggle is never silently dropped.

Residual risk (accepted): two togglePin/prune RMWs interleaving within milliseconds can lose one update. Pin toggles are human-paced (seconds apart); the pre-v2 failure mode required only a stale process and ANY later toggle, which is now impossible.

## Runtime Verification

Prerequisite: TUI process started AFTER 2026-08-15 12:25 binary swap (old processes keep the pre-fix inode).

1. Pin a session in a TUI (e.g. the ez-omo-config one). Confirm it appears in `~/.local/state/opencode/session.json`.
2. From any other TUI in the same project, trigger a `session.deleted` event (delete a throwaway session), or wait for routine cleanup.
3. Watch `.sisyphus/pin-watch.log`: the prune write must contain the NEWER pin still present (content diff removes only the deleted id).
4. Reboot test: reboot, reopen TUI, pin marks must survive (pre-fix behavior: stale TUI prune wiped them).
5. **Regression signal**: any `MOVED_TO session.json` write whose content drops ids that were present in the previous write and are NOT the deleted session id.

## Reapply Instructions

Source commit e7f5981ea on branch `fix/link-click-v1.18.5-solidjs` in `~/src/opencode` (branch carries all other live v1.18.5 patches — never reapply from a bare v1.18.5 tag or the other patches drop out). After an opencode version upgrade: cherry-pick e7f5981ea onto the new patch branch, rebuild with `OPENCODE_VERSION=<new-version> bun run script/build.ts --single --skip-install --skip-embed-web-ui`, and re-run the Runtime Verification steps above.

Fix should also be submitted upstream to `sst/opencode` once verified live (PR per patch-opencode skill; compliance bot requires all six template headers).
5. Verify the fix using the Runtime Verification steps above on both single-process and multi-process scenarios.
