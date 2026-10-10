# Acknowledged test failures

Known **pre-existing** failures with a verified cause. `tests/run_regressions.sh`
and `tests/run_all.sh` read this file and count a listed test's failure as
`acknowledged` instead of `failed`, so the gate reflects only NEW regressions.

## Contract (read by the harness)

- One row per test. The **first table column** is the test script basename
  without the `.sh` suffix (e.g. `028-continuation-wedge-fastfail`,
  `test_public_safety`). The harness matches `^\| <name> \|`.
- Add a row only with a verified cause + evidence. Delete the row when fixed.
- `disposition` is informational: `acknowledged` (environmental/stale, no fix
  planned) or `workorder` (real defect tracked in `.omo/workorders/`).
- This file is additive: it never changes a test's own pass/fail logic, only
  how the harness tallies its result.

## Registry

| Test | Cause | Date | Evidence | Disposition |
|------|-------|------|----------|-------------|
| 028-continuation-wedge-fastfail | Wedged test server's hook-snapshot times out rc=124 (20s > 15s deadline under load) | 2026-10-10 | rc=28 on GET /session/status | acknowledged |
| bash-group-cleanup-timeout | Timing flake; passes on isolated re-run (5245ms in [5000,15000]); fails under parallel load | 2026-10-10 | isolated re-run PASS 2026-10-10 | acknowledged |
| bash-pipe-wedge-bounded | Wedge repro broken: escaped pipe holder exits in 446ms (found=1) instead of wedging >=5s; bounded-kill unverifiable | 2026-10-10 | WEDGE_DUR=446ms, WEDGE_FOUND=1 | acknowledged |
| sse-queue-bounded | Pinned pattern `Queue.sliding` gone from ~/src/opencode (checkout v1.18.31-39-g3e77f50); reconcile at next update-to-latest pass | 2026-10-10 | grep miss in handlers/event.ts | acknowledged |
| sse-socket-leak | Pinned pattern `reader.cancel` gone from sdk serverSentEvents.gen.ts; same source drift as sse-queue-bounded | 2026-10-10 | grep miss in sdk/js/src/gen/core/serverSentEvents.gen.ts | acknowledged |
| 2026-10-09-local-tool-stall-exemption | References missing worktree ~/src/opencode-wt-stall; patch entry active but source worktree removed | 2026-10-10 | ls: no such file or directory | acknowledged |
| test_public_safety | password-pattern FALSE POSITIVE (scripts/require-idle-opencode.sh:64,73,76 local `password=''` var + `OPENCODE_SERVER_PASSWORD=*` env parsing, no secret) AND absolute-path hits (workorder) | 2026-10-10 | scan output lines 622-625, 646 | acknowledged |
| 006-guard-plugin-absent | Test asserts plugins/live-patch-guard.ts must be absent but the file exists | 2026-10-10 | file present | workorder |
| 013-lookat-fallback-patience | `LOOK_AT_FALLBACK_PATIENCE_MS = 60000` missing from live OMO dist ~/oh-my-openagent-v4.19.2/dist/index.js (protected runtime) | 2026-10-10 | grep miss in dist/index.js | workorder |
| 018-plugin-export-surface | configs/opencode/fallback-watch.mjs exports non-contract symbols (FallbackWatchPlugin, buildDeclaredSets, classifyAgentTurn) | 2026-10-10 | BAD SURFACE distinct-from-default=[...] | workorder |
| test_artifact_manifest | sk- secret scan hit in configs/opencode/opencode.json (LiteLLM router key inline) | 2026-10-10 | scan output line 47 | workorder |
| test_patch_lockfile | lockfile patch_ids opencode--question-stream-stall-guard + opencode--tui-error-toast-directory-scope have no active registry entry | 2026-10-10 | scan output line 530 | workorder |
