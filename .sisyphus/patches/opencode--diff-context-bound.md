---
patch_id: "opencode--diff-context-bound"
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
verification_strength: "discriminative"
required_evidence: "runtime"
surfaces: "server-api, cli-run, tui-interactive"
---

# OpenCode bounded diff patches (RC1 — write amplification)

## Problem

`diffFull` rendered every summary.diffs patch with `context: Number.MAX_SAFE_INTEGER` — every line of both file versions embedded per modified file, re-serialized into message rows, every `message.updated` event, export, and share. Observed worst: 15.2 MB message row, 40 MB event (DB at 49.5 GB).

## Patch Description

Source commits `a73db3c331` (fix) + `a4b4662ebb` (tests) on fork branch `fix/v1.18.31-diff-context-bound` (base: `fix/v1.18.31-question-stall-watchdog`). Patch context bound 3; per-file patch cap default 256 KiB via `OPENCODE_MAX_PATCH_BYTES` (0 = upstream behavior). Bounded output keeps hunk-header consistency and an explicit elision marker; `additions/deletions/files` metadata computed from the full diff (unchanged). Blobs larger than the cap produce header-only entries.

## Verification

- Structural: `bun test test/snapshot/amplification.test.ts` (4 pass), regression pair `tests/regressions/2026-09-29-diff-context-bound.{sh,kill.sh}` (both green, kill proved).
- Runtime (pre-install, dist binary 1.18.31-p3): scratch session modified one line of a 20k-line file; resulting user-message `summary.diffs` patch = 98 bytes with exact adds/dels=1/1 and elision marker (upstream would be ~900 KB). Evidence: /tmp/opencode/probe.oBGgqE (scratch, ephemeral) — reproducible via plan T6(a).
- Post-install TUI/server-surface verification PENDING (operator swap gate). Keep `runtime_effective: false` until observed on live TUI diff summary + revert.

## Status note

`status: staged` until branch is pushed to EZotoff/opencode (pre-push hook currently SIGSEGVs on pre-existing typecheck debt — operator decision pending) and binary swapped (operator approval).
