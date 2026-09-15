---
patch_id: "opencode--tui-pinned-session-window"
dependency: "opencode"
target_file: "packages/tui/src/component/dialog-session-list.tsx"
target_install_path: "/home/ezotoff/.opencode/bin/opencode"
source_repo: "/home/ezotoff/src/opencode"
status: "active"
applied_date: "2026-09-15"
dep_version: "1.18.5"
runtime_effective: true
runtime_effective_note: "Observed on the real TUI surface 2026-09-15: veran session dialog renders the Jul 22 pin 'Reconciliation Workbench - UI fix' under the Pinned header via the by-ID fetch (verified by dialog search filter capture), plus 18 further window-external cross-project pins that the browse/sync windows never contained. Source commit e5e715270 on fix/tui-pinned-session-window-v1.18.5; installed binary sha256 a40da485."
upstream_issue: "none"
verification_pattern: "pinned"
verification_note: "Bun minification strips comments and renames locals; this patch adds no unique string literal or property key, so pattern-presence is a weak pre-filter only. Authority rests on the source commit (e5e715270), the regression test (tests/regressions/021-pinned-session-window-fetch.sh), and the runtime_effective flag with the TUI observation recorded in runtime_effective_note."
surfaces: "tui-interactive"
---

# OpenCode TUI pinned sessions vanish under session-list pressure — FIXED locally 2026-09-15

## Problem

The session dialog's Pinned section only showed pins whose sessions were also inside the
"100 most recently updated" browse window (or the 30-day/100 sync window). In a busy
project — or under a session-spam flood (see the veran benchmark-runner incident,
2026-09-14: ~1,900 junk sessions) — every pinned session fell out of that window and the
entire Pinned section silently emptied. Users experienced this as "losing all pinned
sessions"; the pin file (`~/.local/state/opencode/session.json`) was never corrupted.

A second aggravator was discovered during the incident: this fork's `Session.list` does
NOT exclude `time_archived` sessions on the HTTP list path (archived rows are returned
with their `time.archived` flag set), so archiving junk cannot shrink the flood. Related
surveillance: `opencode--tui-pinned-session-race` (pin-file write races, separate defect).

## Patch Description

In `packages/tui/src/component/dialog-session-list.tsx`:

- Added a `fetchedPinned` signal plus a one-shot-per-ID fetch effect: for every pinned
  session ID that is not present in the current browse/search/sync results, the dialog
  calls `sdk.client.session.get({ sessionID })` and stores the result.
- The `sessions` memo's rescue path now consults `synced.get(id) ?? fetchedPinned()[id]`,
  so the Pinned section renders pins regardless of any list window.

Failures (deleted/foreign sessions) are swallowed per-ID and never retried, so deleted
pin entries stay inert. Before: pins were visible only while inside the windows.
After: pins are window-independent.

## Verification

Weak pre-filter (minification strips the added comment markers):

```bash
grep -c "pinned" ~/.opencode/bin/opencode   # >0, not authoritative
```

Authoritative checks:

```bash
# Source commit carries the fix
cd ~/src/opencode && git log --oneline -1 fix/tui-pinned-session-window-v1.18.5
# expect: e5e715270 fix(tui): fetch pinned sessions by ID ...

# Installed binary is the patched build
sha256sum ~/.opencode/bin/opencode
# expect: a40da48545acfc8659948d1758aa390d8e63ab281cc011f30a1bf16936b01299

# Regression test
bash tests/regressions/021-pinned-session-window-fetch.sh
```

## Runtime Verification

- Surface: tui-interactive (veran project, `oa` attach to 127.0.0.1:3030).
- 2026-09-15: fresh TUI, session dialog opened (`<leader>l`); Pinned section rendered 19+
  entries including window-external pins from mysocial/ez-omo-config/ez-omo-bench
  (impossible under the old windows). Dialog search filter for "Recon" rendered
  "Reconciliation Workbench - UI fix" (Jul 22, veran) under the Pinned header —
  this session was outside both the newest-100 browse window and the 30-day sync window.
- Captured via tmux `capture-pane` during the restore session.
