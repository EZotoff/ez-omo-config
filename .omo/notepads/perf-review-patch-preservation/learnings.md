# Learnings — perf-review-patch-preservation

Conventions, patterns, and successful approaches discovered during work on this plan.

_Auto-scaffolded by /start-work. Append new entries below - never overwrite._

---

## Task 2 — Watcher efficiency metrics (2026-09-16)
- Journal 14d: 5131 lines / 1,482,631 B (~0.74 MB/week, ~367 events/day); peak day 2026-09-14 (2514 lines).
- Class breakdown: OMO-dist-suspect 4925 (96%, burst during Sep 13–14 rebuild+reapply), backup-write 25, binary-event 6, verify-passed 4, verify-failed 2, dist-not-found 0, unclassified 169 (multi-line verifier table output + boot separators). Sum == 5131.
- Live: active, MainPID 4899, up since Sep 13 23:49 CEST; VmRSS 2168 kB, delta 0 kB over ~87 s (threshold 10240); cgroup CPU 44.17 s since restart; MemoryCurrent 626688 B (MemoryPeak unsupported on this systemd).
- Deployed copy (~/.sisyphus/scripts/watch-runtime-patches.sh) byte-identical to repo; deployed mtime 2026-09-09 08:30 vs repo commit 2026-09-09 08:36 — no drift.
- Watch scope: 13 entries ~/.opencode/bin (filter → opencode$) + 2114 dist files (inotify -r). Recursive dist watch is the cost driver but RSS shows it cheap.
- err_count=62 is journalctl output lines, not entries; real verify-failure events = 2.
- Coverage caveat: journal spans pre-restart window (Sep 09–13, old MainPID) + post-restart.
- Evidence: .sisyphus/evidence/perf-review-patch-preservation/task-2/ (watcher-metrics.json, watcher-journal-14d.log, class-breakdown.tsv, watcher-metrics-edge.log)

## task-1: verify-pipeline cost & failure attribution (2026-09-16)
- 427 paired runs / 14d (events=428, 1 unpaired tail). p50=6.33s, p95=9.30s, max=18.83s, mean=6.89s; cadence median 30.05min.
- Failures 118/427 (27.6%): verify-stale 96 (incl missing-target), drift 22, both 0, other 0. Reconciliation delta 0.
- Attribution caveat: journal MESSAGE lacks `script[PID]` syslog prefixes — content-based attribution (Summary line, LIVE-CONFIG DRIFT, VERSION-DRIFT rows) is the reliable anchor.
- Planning baseline (101/301, ~57 stale, ~15 drift) superseded by live-journal numbers (118/427, 96/22).
- fail_transient_share=0.161 (commit within ±35min in .sisyphus/patches/ or configs/, 42 commits/14d, OR next run green within 1h; 8 green-next).
- Fresh-run cost: verify-live-patches.sh median 13.54s (13.38–13.64); tests/test_patch_entries.sh median 0.33s. Fresh verify rc=1 in worktree (1 stale + 1 missing-target from worktree checkout) — timings valid.
- Error path: `verify-live-patches.sh /nonexistent/fake` → rc=1, 9 MISSING-TARGET rows, zero unbound-variable crashes; alert marker mtime unchanged (no false write).
- Unit confirmed: 2 ExecStart lines; first-exec fail suppresses second, so drift-fail requires verify pass — explains both=0.
- journal_coverage: full 14d retained (first line 2026-09-02T…), disk 4.0G.
- Evidence: .sisyphus/evidence/perf-review-patch-preservation/task-1/{verify-pipeline-metrics.json,journal-extraction.log,fresh-timing-and-error-path.log}
