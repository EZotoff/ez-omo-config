---
patch_id: "opencode--snapshot-track-skip-unchanged"
dependency: "opencode"
target_file: "packages/opencode/src/snapshot/index.ts"
target_install_path: "/home/ezotoff/.opencode/bin/opencode"
source_repo: "/home/ezotoff/src/opencode"
status: "staged"
applied_date: "2026-09-29"
dep_version: "1.18.31-p3"
runtime_effective: false
upstream_issue: "none"
verification_pattern: "OPENCODE_MAX_PATCH_BYTES"
verification_strength: "weak"
required_evidence: "runtime"
surfaces: "server-api, cli-run, tui-interactive"
---

# OpenCode snapshot track() skip when worktree unchanged (RC3)

## Problem

`track()` ran `git add --all --sparse` + `write-tree` ≥2×/assistant turn; the add rewrites the full index even with zero changes (large repos → MBs per step, ~450 KB/s sustained daemon writes).

## Patch Description

Source commit `237a0a7800` on fork branch `fix/v1.18.31-diff-context-bound`: skip staging + exclude-file rewrite when changed/untracked candidate lists are empty and no removals ran; still runs `git write-tree` for the authoritative tree hash (NEVER returns a cached hash — restore()/read-tree can mutate the index); initializes a missing index on first use. Shares the P1 build; `verification_pattern` above only proves the sibling patch's string — the regression pair below is the real structural check for this patch.

## Verification

- Structural: unit tests in `a4b4662ebb` (index-mtime unchanged on second track, hash identical, post-restore hash authoritative); regression pair `tests/regressions/2026-09-29-track-skip-unchanged.{sh,kill.sh}` green, kill proved.
- Runtime PENDING: post-swap measurement (plan T8) — daemon write rate under campaign load must drop ≥50% vs the 2026-09-29 baseline (~450 KB/s). Keep `runtime_effective: false` until measured.

## Status note

`status: staged` until branch pushed to EZotoff/opencode and binary swapped (operator gates).
