---
patch_id: "opencode--event-scope-attach-congestion"
dependency: "opencode"
target_file: "packages/opencode/src/server/routes/instance/httpapi/handlers/event.ts, packages/opencode/src/server/routes/instance/httpapi/handlers/event-scope.ts, packages/tui/src/context/sync.tsx, packages/tui/src/context/sync-guard.ts"
target_install_path: "/home/ezotoff/.opencode/bin/opencode"
source_repo: "/home/ezotoff/src/opencode-attachfix"
status: "active"
applied_date: "2026-09-30"
dep_version: "1.18.31-p2"
runtime_effective: true
upstream_issue: "none"
verification_pattern: "searchParams\\.get\\(\"scope\"\\)|session_directory_filter_enabled"
verification_strength: "discriminative"
required_evidence: "runtime"
surfaces: "server-api, tui-interactive"
---

# OpenCode /event scope: attach-viewer loopback + RSS regression fix

## Problem

Each `opencode attach` viewer on a shared `opencode serve` received — and stored —
every other directory's message-class events. Because the committed `event.ts`
removed the SSE directory filter (`opencode--sse-directory-filter-removal`) to
restore cross-directory delivery, every busy session's full message payloads were
fanned out to every subscriber. Measured 2026-09-30 (STOP-gate, pre-fix): ONE idle
attach window received 1.38 GB over ~165 s (~8 MiB/s loopback) while a single
foreign-directory session streamed; ~99.8% of the subscriber's SSE bytes were
foreign `message.*` frames (dominant carrier `message.updated`, 92.3% — it resends
the full message on every delta; `message.part.updated` resends whole tool outputs).

## Patch Description

Two layers, one binary (TUI ships in-package):

- **S1 server** (`event.ts` + new `event-scope.ts`): the SSE stream now drops
  high-volume message-class events (`message.updated|removed`, `message.part.*`,
  `todo.updated`, `session.diff`) whose `location.directory` differs from the
  subscriber's instance directory, unless the client opts back into the firehose
  with `?scope=all`. Low-volume classes (`session.updated|status|created`,
  heartbeats, `file.watcher.updated`, `server.instance.disposed`) are never
  filtered, preserving the cross-directory-observer use case the removal patch
  restored.
- **S2 client** (`sync.tsx` + new `sync-guard.ts`): defense-in-depth — the
  existing `session_directory_filter_enabled` guard is extracted into the pure
  `shouldApplySessionEvent(store, sessionID, evDirectory, sdkDirectory, kv)`
  helper and applied to all per-session-writing event cases
  (`message.updated/removed`, `message.part.updated/delta`, `todo.updated`,
  `session.diff`, `permission.asked`). Semantics: own-directory events apply,
  already-known sessions always apply, kv-off bypasses — identical to the
  `session.updated` insert guard (`opencode--tui-session-directory-scope`).

## Verification

Pattern (necessary, NOT sufficient — function symbols are minified away in the
bun dist; this string literal survives and is ABSENT in pre-fix binaries):

```bash
grep -a -c 'searchParams.get("scope")' /home/ezotoff/.opencode/bin/opencode
```

Expected: ≥1. Pre-fix live binary: 0. Provenance: build receipt
`8c3a0f0ae872d86e27a214633994571bce5770e69e3b4f62d06c9cdf73b0862e` binds
generation `opencode-1.18.31-patches.2` → source_head `687ac6ea84`.

Unit tests (source): `packages/tui/src/context/sync-guard.test.ts` (6 cases),
`packages/opencode/test/server/event-scope.test.ts` (6 cases) — both RED before,
GREEN after.

## Runtime Verification

2026-10-01 live gate on :3030/:3040 after receipted install + ordered restarts
(bench→interactive→headless fresh PIDs on `8c3a0f0ae872`):

1. **S1 behavioral A/B**: during an active foreign-directory busy session, a
   scoped `/event` subscriber received ZERO `message.*` frames from that session
   (0.01 MB total stream: only `session.updated/status`, heartbeats, watcher).
   Pre-fix equivalent probe: 19–90 MB dominated by foreign `message.updated`.
2. **Loopback gate**: 0.949 MiB/s summed on :3030/:3040 over 195 s with a busy
   foreign session running and 6 attach windows open (gate ≤2 MiB/s).
   Idle-state floor: 0.000 MiB/s.
3. **RSS/swap**: attach-window RSS stable over the window (Δ −62…+12 MB; several
   shrinking); swap delta ~+5.8 MB across all windows (~0). Interactive server RSS
   FELL 2.13 GB → 1.30 GB post-install as foreign-session state stopped
   accumulating. Note: absolute <300 MB/window applies to clients started on the
   fixed binary; the operator's legacy attach processes (pre-fix TUI code)
   stabilize but carry pre-fix accumulation.
4. **History render**: a 37.8 MB-transcript session (`bonsai-perf-program`,
   `ez-omo-bench`) opened in a fresh attach on the fixed binary — messages render,
   PageUp scrollback shows deep history, window survives continuation restarts.
5. Regression pair harness: see `tests/regressions/attach-fanin-*.sh` (byte
   ceiling against a scratch-dir busy session).

## Reapply Instructions

1. Worktree from the receipted lineage (`59e750a34a` or later canonical tip);
   never build from the dirty main tree.
2. The full fix is commit `687ac6ea84995f89449fcf3ccff197e23d2761d6` on
   `EZotoff/opencode` (`fix/event-scope-attach-congestion`, FF of canonical_ref
   branch `fix/v1.18.31-question-stall-watchdog`). Cherry-pick onto the aggregate
   branch carrying all other active patches, then build + install via the
   transactional installer (`OPENCODE_SRC=<worktree>
   scripts/build-and-install-opencode.sh build` then `install <dist-bin>` — the
   installer refuses dirty or unpushed heads; commit+push precede build).
3. Ordered restart bench→interactive→headless via detached
   `restart-with-continuation.sh --restart` units; verify fresh PIDs + binary SHA
   (`build-and-install-opencode.sh verify`).
4. Re-run Runtime Verification 1–4 before keeping `runtime_effective: true`.

## Durable Alternative

Upstream a directory-scoped subscription option for the global `/event` stream
(the `?scope=all` semantics) so shared-server attach clients do not need a
client-side guard. Status: not-yet-pursued.
