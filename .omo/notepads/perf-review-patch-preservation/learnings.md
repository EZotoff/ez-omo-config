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

## task-6: fork + patched-binary maintenance burden (2026-09-16)
- Registry active total = 28 (not the plan's stale baseline 26): 19 oh-my-openagent + 9 opencode. Layer census (target_file heuristic): source 20, dist 6, config 2, unclassified 0 — sums to 28.
- Layer heuristic caveat: omo--family-reasoning-efforts has a source target_file but its note says the fix is dist-applied and source is NOT yet patched — the target_file heuristic misclassifies it as source. Secondary `grep -l 'dist/index.js'` matches 15 entries (source patches rebuilt into dist inflate this).
- Surfaces census across 9 opencode entries: tui-interactive 6, cli-run 1, server-api 0, no-surfaces-field 3 (command-hook-cancellation, commit-policy-unblock, sse-directory-filter-removal). turn-summary-timestamp declares both cli-run+tui-interactive.
- Binary alignment: live 1.18.5 vs 9 opencode dep_versions → 8 match, 1 not (sse-directory-filter-removal = 1.17.9-local, runtime_effective false → acknowledged drift).
- Tree-state drift vs plan baseline: oc branch is fix/tui-pin-directory-guard-v1.18.5 (baseline expected fix/tui-pinned-session-window-v1.18.5) — branch advanced by the newest patch; omo tag is v4.19.2-patches.1-12-ge6bb8b059 (baseline v4.19.2-patches.1) — 12 commits past the advertised tag. Both trees dirty (oc 2, omo 1), unchanged before/after probes.
- Reapply-cost history: 9 events recorded; only the 2026-09-08 dist-destroy incident has a wall-time (~2h outage). The 2026-07-13 @latest loss (8/9 patches) and the 2026-08-01 cutover (4 patches drifted 10+ days) are the two silent-loss events; effort was never recorded for any reapply.
- Evidence: .sisyphus/evidence/perf-review-patch-preservation/task-6/{maintenance-burden.json,reapply-events.tsv,tree-state.log}

## Task 5 — Alert-path integrity & false-positive metrics (2026-09-16)
- Journal 14d: 74 fires (first 2026-09-09 08:23 — unit/journal horizon starts there, not full 14d). fires/day: 11.06 over observed span, 5.29 naive /14. Supersedes Sep-15 baseline of 49.
- Latency start→INTEGRITY-ALERT: p50 7.0s, p95 13.0s; CPU median 8.36s per fire (each fire re-runs verify-live-patches serially).
- Marker lifecycle: zero rm/unlink hits in scripts/integrity-alert.sh + systemd/user/ → no autoclear. Baseline marker (2026-09-15 07:25) persisted ~41.5h and was only ever OVERWRITTEN by the next fire (2026-09-16 00:56:55), never cleared by a green run. Staleness vs first subsequent green run: pending (no green run yet after latest write).
- False-positive classification (±35min commit in .sisyphus/patches/|configs/ OR immediately-next integrity run green): 27.0% false (17 near-commit, 10 next-run-green), 54/74 true persistent failures.
- Hermetic sandbox: env -i HOME=/tmp/opencode/alert-test PATH=<curated bin symlink-farm> EZ_OMO_CONFIG_REPO=<WT> bash scripts/integrity-alert.sh sandbox-test-unit → rc 0, sandbox marker created with INTEGRITY-ALERT content, real marker epoch 1789513015 unchanged before/after. PATH=/bin alone would NOT trigger the notify-send guard on this merged-usr box (/bin/notify-send is a usrmerge symlink) — a curated bin dir minus notify-send is the reliable guard-exercise mechanism.
- Evidence: .sisyphus/evidence/perf-review-patch-preservation/task-5/ (alert-path-metrics.json, alert-journal-14d.log, sandbox-run.log)

## Task 3 — Regression corpus runtime + pair-value mapping (2026-09-15)

- **Actual corpus is 28 pairs (56 files), not 27.** README claims 25 pairs (50 files) → drift |28−25| = 3. The plan's own checkbox-3 acceptance ("exactly 54 rows / 27 rows") is stale by 1 pair; recorded all 56 timing rows + 28 map rows rather than silently dropping a pair.
- **Two duplicate numeric prefixes**, not one: `021-` (clipboard-display-env, pinned-session-window-fetch) AND `022-` (pin-directory-guard, worktree-create-tui-handoff). Recorded only.
- **Corpus is fully green**: 28/28 tests pass, 28/28 kill-tests prove, harness rc=0, TOTAL 9.45s. Zero red tests → no red-*.log needed.
- **Classification split (28)**: 7 ACTIVE-anchored, 0 NON-ACTIVE-anchored, 11 ORPHAN, 10 INFRA.
- **ORPHAN cluster**: review-enforcer (014/015/016/018/019), git-safety (010/011), worktree plugin (009/022), clipboard (021), provider-connect-retry near-empty (2026-08-02). These guard repo plugins/configs that have NO `.sisyphus/patches/*.md` entry — the corpus is broader than the patch registry.
- **Near-miss anchors rejected**: `oh-my-openagent--start-work-worktree-teardown` (mentions worktree_start but is about teardown receipts) and `omo--sync-delegate-task-result-bloat` (touches provider-connect-retry.mjs but the ZERO-token branch, not the near-empty branch).
- **Timing method**: external `date +%s%N` loop replicating harness order (.sh then .kill.sh), output to /dev/null. 6210 ms outlier on 2026-08-02 (bun unit harness) under 5-agent CPU contention.
- **No residue**: `git status --porcelain -- tests/` empty before and after.

## Task 5 — independent re-verification + marker-persistence correction (2026-09-16)
- Re-ran the full 14d forensics independently; all headline numbers reproduce: 74 fires, p50 7.0s / p95 13.0s, CPU median 8.36s, false-positive union 20/74 = 0.2703 (17 near-commit, 10 next-run-green, 7 overlap), 54 true persistent failures.
- **Correction to the earlier Task 5 note**: the marker-persistence figure "~41.5h" is wrong. The 2026-09-15 07:25:37 marker persisted only 19819s (5.5h) until the next fire at 12:55:56; its first subsequent green run was 07:55:31 (1794s to recovery). The **max observed stale window** across the journal is 135226s (37.56h), 2026-09-13 17:51:51 -> 2026-09-15 07:25:37, spanning 68 green runs. Only 8 of 73 inter-fire windows contain any green run.
- marker_staleness_after_last_fail_s is null (current generation 2026-09-16 00:56:55 has no subsequent green run yet); the max-observed value is recorded as marker_staleness_max_observed_s=135226.0.
- Sandbox re-exercised independently: env -i HOME=/tmp/opencode/alert-test PATH=/tmp/opencode/alert-test/bin EZ_OMO_CONFIG_REPO=<WT> bash scripts/integrity-alert.sh sandbox-test-unit -> rc 0, guard branch taken (notify-send NOT resolvable under farm PATH), sandbox marker written with INTEGRITY-ALERT content, real marker epoch 1789513015 unchanged before/after.
- Evidence: .sisyphus/evidence/perf-review-patch-preservation/task-5/ (alert-path-metrics.json, alert-journal-14d.log, integrity-check-14d.log, sandbox-run.log)

## Task 7 — component verdict matrix (2026-09-16)
- Roll-up: WORKS 1 (registry) · DEGRADED 4 (watcher 106KB/day journal, corpus 11 ORPHANs, alert fp 27%, fork/binary) · BROKEN 2 (verify fail rate 23.19% excl. maintenance, alert delivery 11.06 fires/day) · UNKNOWN 1 (timer cadence coverage — host-awake denominator absent from Wave-1 evidence; naive 24/7 coverage 63.6%).
- Verify duration alone is WORKS (p95 9.30s) but fail rate 118×(1−0.161)/427=23.19% → section BROKEN; worst-sub-band rollup, no softening.
- Alert delivery is BROKEN under BOTH the observed-span (11.06/day) and naive /14 (5.29/day) readings — journal-horizon ambiguity doesn't change the verdict.
- Watcher 105,902 B/day = 105.9 KB/day lands just inside the DEGRADED band (100–500); RSS and suspect-class sub-verdicts are WORKS (burst fully mapped to 2026-09-14/15 reapply events).
- Consistency check: recompute.py re-derives all 8 rows from raw JSON/TSV evidence → 8/8 AGREE, 100%, rc=0 (task-7/consistency-check.log).
- Evidence: .sisyphus/evidence/perf-review-patch-preservation/{analysis/verdict-matrix.md, task-7/{consistency-check.log, gaps-section.md, recompute.py}}
