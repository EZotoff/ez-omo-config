---
patch_id: "opencode--tui-subagent-spinner"
dependency: "opencode"
target_file: "packages/tui/src/component/dialog-session-list.tsx"
target_install_path: "/home/ezotoff/.opencode/bin/opencode"
source_repo: "/home/ezotoff/src/opencode"
status: "active"
applied_date: "2026-09-17"
dep_version: "1.18.5"
runtime_effective: true
runtime_effective_note: "Observed live 2026-09-17 ~13:55 on the shared daemon (:3030). A/B: scratch parent session dispatched a quick-category sub-agent in background and ended its turn; server /session/status confirmed parent=idle + child=busy at capture time; tmux-driven attach TUI Sessions dialog showed the braille spinner frame on the parent row (capture: /tmp/opencode/dialog-final.txt, line '⠏ spinner-ab-test'). Pre-fix captures showed no spinner on the same shape."
upstream_issue: "none"
verification_pattern: "parentID"
verification_strength: "weak"
required_evidence: "provenance"
verification_note: "WEAK pre-filter only — 'parentID' is a pre-existing property key in this file (both in source and binary); presence proves nothing about THIS aggregation. Bun minification strips comments and renames locals, and the patch adds no unique string literal. Authority rests on the source commits (8ed469559 + 8257e338c on fix/tui-subagent-spinner-v1.18.5), the regression pair (tests/regressions/024-subagent-spinner.sh + .kill.sh), and the runtime_effective flag with the A/B observation recorded above."
surfaces: "tui-interactive"
---

# OpenCode TUI: spinner for sessions with running sub-agent children

## Problem

Sub-agent (child) sessions are filtered out of the Sessions dialog
(`x.parentID === undefined` in `orderByRecency` and the `sessionMap`
builder), and the per-row spinner decided only on the session's OWN
`session_status`. A parent session whose work runs through a background
sub-agent (parent idle, child busy) therefore showed no spinner and looked
inactive in the list — the exact state the spinner exists to communicate.

## Patch Description

`packages/tui/src/component/dialog-session-list.tsx` (commits `8ed469559` +
`8257e338c` on `fix/tui-subagent-spinner-v1.18.5`, based on `ed579472d`):

Inside the `options()` memo, before building rows, the dialog aggregates
busy/retry child statuses into a `workingChildParents` set: every session
with a `parentID` whose `session_status.type` is `busy`/`retry` adds its
parent. The row-level `isWorking` check becomes own-status OR membership in
that set.

Critical detail (second commit): the browse/search resources query the
server with `roots: true`, so children are NEVER in `sessions()` — the
aggregation must union `sessions()` with the unfiltered
`sync.data.session` list (which is directory-scoped and includes children
within the 30-day window). The first commit iterated only `sessions()` and
was proven ineffective live; kept in history for the A/B record.

## Verification

Pattern (weak pre-filter only, see verification_note):

```bash
grep -a -c "parentID" ~/.opencode/bin/opencode
```

Source structure is pinned by
`tests/regressions/024-subagent-spinner.sh` (paired `.kill.sh` proves
detection of both the aggregation strip and the sync-union removal).

## Runtime Verification

1. Create a scratch session in the attach directory; prompt it to dispatch
   a background sub-agent (category with a working model — explore's
   primary hit its 2026-09 monthly cap and children flicker through retry
   limbo) and end its turn immediately.
2. Poll `GET /session/status?directory=<dir>` until parent is absent (idle)
   and the child reports `busy`.
3. Open the Sessions dialog (leader=ctrl+x, then `l`): the parent row must
   show a spinner frame while the child is busy, and must not while idle.

### Observed 2026-09-17 (PASS)

Parent `ses_f50d93748…` idle, child `ses_f50c953c1…` busy → dialog row
rendered `⠏ spinner-ab-test`. Own-status path unchanged (busy parent rows
spin as before). Evidence: `/tmp/opencode/dialog-final.txt`.

## Current Runtime Status

Effective as of 2026-09-17, binary rebuilt at 1.18.5 from
`fix/tui-subagent-spinner-v1.18.5` (HEAD `8257e338c`).
