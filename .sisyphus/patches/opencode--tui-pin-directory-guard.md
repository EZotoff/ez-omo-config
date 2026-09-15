---
patch_id: "opencode--tui-pin-directory-guard"
dependency: "opencode"
target_file: "packages/tui/src/component/dialog-session-list.tsx"
target_install_path: "/home/ezotoff/.opencode/bin/opencode"
source_repo: "/home/ezotoff/src/opencode"
status: "active"
applied_date: "2026-09-15"
dep_version: "1.18.5"
runtime_effective: true
runtime_effective_note: "Observed live 2026-09-15 ~23:10 on the shared daemon (:3030), A/B via tmux-driven attach TUIs at --dir /home/ezotoff/AI_projects/veran. OLD binary (pre-guard, pin-window build): Pinned section listed 12+ foreign-directory pins with directory badges (rag_base, traveller, ez-omo-config, mysocial, llm-review). PATCHED binary: Pinned section listed ONLY exact-veran pins (14 entries, slots 1-7 intact), zero foreign entries. Captures: .sisyphus/evidence/opencode--tui-pin-directory-guard/ (dialog-old-binary.txt, dialog-new-binary.txt)."
upstream_issue: "none"
verification_pattern: "session_directory_filter_enabled"
verification_note: "NECESSARY, NOT SUFFICIENT — this kv key is shared with the opencode--tui-session-directory-scope patch (sync.tsx/app.tsx), so presence proves nothing about THIS guard. The structural pin is regression pair tests/regressions/022-pin-directory-guard.sh (+ .kill.sh) against the dialog source; runtime effectiveness is pinned by ## Runtime Verification and the A/B captures."
surfaces: "tui-interactive"
---

# OpenCode TUI: foreign-directory pinned sessions hidden from the session dialog

## Problem

`opencode--tui-session-directory-scope` (2026-09-12) made the session list and
event store scoped to the attach directory. But `opencode--tui-pinned-session-window`
(2026-09-14) added a fetch-by-ID path (`session.get({sessionID})`) for pinned
sessions outside the list windows — and `GET /session/:id` is NOT
directory-scoped server-side. Result: every cross-directory pin (veran's pin
store holds pins from mysocial, ez-omo-config, ez-omo-bench, rag_base,
traveller, llm-review) materialized in the dialog's Pinned section and
`extra` rescue path of ANY attached TUI, reintroducing exactly the
cross-project leakage the scope patch had eliminated. Found 2026-09-15; the
scope patch's `verification_pattern` still grepped clean (APPLIED), so the
integrity timer never fired — pattern presence ≠ invariant intact.

## Patch Description

`packages/tui/src/component/dialog-session-list.tsx` (commit `ed579472d` on
`fix/tui-pin-directory-guard-v1.18.5`, based on `e5e715270`):

The `sessions()` memo's `extra` rescue path (current session + pins) now drops
any session whose `directory` differs from `sdk.directory` while the
`session_directory_filter_enabled` kv filter is on (default) and `sdk.directory`
is defined. The current session itself is always exempt. Strict policy decided
by the owner 2026-09-15: NO foreign pins visible at all (no count-only group).
Foreign pins remain fully visible in the TUI attached to their own directory,
so the pin-window guarantee ("pins are never lost to list pressure") still
holds per-directory.

Quick-switch slots needed no change: `local.session.slots()` resolves only
from `sync.data.session`, whose inserts are already guarded by the scope patch.

## Verification

Pattern (necessary, NOT sufficient):

```bash
grep -a -c "session_directory_filter_enabled" ~/.opencode/bin/opencode
# expect ≥ 2 (sync.tsx + dialog guard literals)
```

Source structure is pinned by `tests/regressions/022-pin-directory-guard.sh`
(paired `.kill.sh` proves detection).

## Runtime Verification

1. Launch a fresh TUI against the shared daemon with the NEW binary:
   `opencode attach http://127.0.0.1:3030 --dir <project-dir>` in tmux.
2. Open the sessions dialog (leader=ctrl+x, then `l`). Expected: Pinned
   section contains ONLY sessions whose directory is exactly the attach dir.
   Regression signal: any entry badged with another directory name.
3. A/B (as executed 2026-09-15): same dialog on the pre-guard backup binary
   shows the foreign pins with badges; patched binary shows none.
4. If regression signal observed → set `runtime_effective: false` and record
   in a ## Current Runtime Status section; do NOT bump dep_version.

### Observed 2026-09-15 (PASS)

Old binary: 12+ foreign pins visible (rag_base, traveller, ez-omo-config,
mysocial, llm-review badges). Patched binary: only the 14 veran pins; zero
foreign entries. Captures:
`.sisyphus/evidence/opencode--tui-pin-directory-guard/`
(dialog-old-binary.txt, dialog-new-binary.txt).

## Reapply Instructions

1. `cd ~/src/opencode` — the fix lives as commit `ed579472d` on
   `fix/tui-pin-directory-guard-v1.18.5` (rebase onto the next release branch;
   single hunk in `packages/tui/src/component/dialog-session-list.tsx`:
   `useKV` import, `foreignPin` helper, guard in the `extra` flatMap).
2. `cd packages/opencode && OPENCODE_VERSION="$(~/.opencode/bin/opencode --version)" PATH=~/.bun/bin:$PATH bun run script/build.ts --single --skip-install --skip-embed-web-ui`
3. Backup: `cp ~/.opencode/bin/opencode ~/.opencode/bin/opencode.backup-<ver>-pin-directory-guard-<ts>`
4. Swap. TUI-ONLY patch — rename-based swap keeps running servers/TUIs on the
   old inode until relaunched (procedure as `opencode--tui-session-directory-scope`).
   The live-patch-guard plugin will block `cp` to the live path; follow the
   audited flow (patch-opencode skill, `OPENCODE_PATCH_GUARD=off` for the
   single swap command after running verify-live-patches.sh).
5. Relaunch a TUI and run the Runtime Verification steps.

## Durable Alternative

Upstream: make `GET /session/:id` honor `x-opencode-directory` (exact-directory
scoping on single-session fetches). This closes the hole for ALL future client
paths rather than guarding each one. Requires a consumer blast-radius review
first (supervisor, ocx, session utilities fetch cross-directory by ID today).
Status: not-yet-pursued.
