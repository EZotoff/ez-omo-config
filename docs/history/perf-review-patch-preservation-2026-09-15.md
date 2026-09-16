# Performance Review: Patch-Preservation Infrastructure

**Date**: 2026-09-15 (evidence collected 2026-09-15/16)
**Analyst**: Sisyphus pipeline (tasks 1–7 Wave-1 measurement + task-7 verdict matrix)
**Scope**: Measured health of the patch-preservation stack — verify pipeline, integrity timer, inotify watcher, regression corpus, patch registry, alert path, fork/binary maintenance — and a decision framework for what to do next.

---

## 1. Executive summary

**The preservation stack detects real problems but buries the operator in false alarms.** Two components are broken, four are degraded, one works, and one cannot be judged yet. The numbers:

- **Verify pipeline — BROKEN**: 23.19% of integrity-check runs fail after excluding transient maintenance noise (118 × (1 − 0.161) / 427; 16.1% of failures sit within ±35 min of a config/patch commit or turn green within 1 h). Duration is fine — p95 9.30 s, well under the 10 s WORKS line — but 96 of the 118 failures are verify-stale findings, many attributable to worktree-checkout artifacts rather than real drift.
- **Alert delivery — BROKEN**: 74 alert fires over the observed 11-day span = 11.06 fires/day (naive /14 reading: 5.29/day). Both readings exceed the >1/day BROKEN threshold. Each fire re-runs the full verifier serially: median 8.36 s CPU per fire.
- **Alert signal quality — DEGRADED**: 27.0% of fires are false positives (20/74; 17 near-commit, 10 next-run-green, 7 overlap), and there is no autoclear path — the worst observed stale marker persisted 37.6 h across 68 green runs.
- **Regression corpus — DEGRADED on value, not speed**: the 28-pair harness runs in 9.45 s total (wall — far under the 5-min WORKS line), all green, all kill-proved — but 11 of 28 pairs are ORPHAN: they guard repo plugins/configs with no `.sisyphus/patches/*.md` anchor.
- **Watcher — DEGRADED by a hair**: journal volume 105.9 KB/day, just over the 100 KB/day WORKS line. Memory (RSS Δ 0 kB) and error attribution (0 unexplained suspect lines) are healthy.
- **Registry — WORKS**: 28 active patches, 0 unjustified `runtime_effective:false` backlog, 0 stale claims. Its residual issues are documentation drift (3 mismatches) — measurable, not structural.
- **Timer cadence — UNKNOWN**: the coverage threshold requires a host-awake denominator that no Wave-1 evidence collected. The naive 24/7 figure (63.6%) cannot distinguish "host asleep" from "timer missing slots".

Section 5 gives, for each component, exactly one recommended direction (keep / tune / instrument-more / retire / consolidate), the cost of taking it, the cost of standing still, and the first task of the follow-up plan. These are options with prices attached, not decisions — the operator decides.

---

## 2. Method

All metrics come from live evidence collected 2026-09-15/16 over a 14-day journal window; nothing in this report relies on planning-baseline numbers (the plan's 101/301-failure baseline was superseded by the measured 118/427). The collection commands, each reproducible on this host:

- **Verify pipeline**: `journalctl --user -u opencode-patch-integrity-check.service --since -14d`, paired-run extraction with content-based attribution (Summary line, LIVE-CONFIG DRIFT, VERSION-DRIFT rows) — the journal MESSAGE field lacks `script[PID]` syslog prefixes, so content anchors are the reliable method. Fresh timing: `hyperfine`-style repeated runs of `verify-live-patches.sh` and `tests/test_patch_entries.sh`. Results in `task-1/verify-pipeline-metrics.json`.
- **Watcher**: `journalctl --user -t opencode-patch-watcher --since -14d` line/byte counts, per-day peaks, class breakdown by message pattern; live RSS/CPU via systemd cgroup properties (`VmRSS`, `MemoryCurrent`, `CPUUsage`). Results in `task-2/watcher-metrics.json`.
- **Corpus**: external `date +%s%N` timing loop replicating the harness order (`.sh` then `.kill.sh`, output to /dev/null) over all 28 pairs, plus a per-pair value map classifying each pair as ACTIVE-anchored / NON-ACTIVE-anchored / ORPHAN / INFRA. Results in `task-3/harness-total-wall.log` and `task-3/pair-value-map.tsv`.
- **Registry**: inventory of all 28 active `.sisyphus/patches/*.md` entries — `runtime_effective:false` ages and justification presence, doc-mismatch scan against `README.md`/`docs/patches.md`, malformed-entry count. Results in `task-4/registry-inventory.tsv` and `task-4/registry-health.json`.
- **Alert path**: `journalctl --user -u opencode-patch-integrity-alert --since -14d` fire counts, start→alert latency, per-fire CPU; false-positive classification (±35-min commit in `.sisyphus/patches/` or `configs/`, OR next integrity run green); marker lifecycle via filesystem mtimes and zero-rm audit; hermetic sandbox exercise (`env -i` with a curated PATH farm that excludes `notify-send`). Results in `task-5/alert-path-metrics.json`.
- **Fork/binary**: dependency censuses of the OpenCode and OMO trees (branch/tag state, dirty-file counts, reapply-event history). Results in `task-6/maintenance-burden.json` and `task-6/reapply-events.tsv`.

Verdicts were then derived mechanically by applying the plan's threshold table to these numbers, with an independent recomputation script re-deriving all 8 matrix rows from the raw JSON/TSV evidence: 8/8 agreement, rc=0 (`task-7/consistency-check.log`). The verdict matrix (`analysis/verdict-matrix.md`) is the single source of verdicts; this report transcribes it without softening.

---

## 3. Per-component metrics

| Component | Metric | Value | Threshold band | Verdict |
|---|---|---|---|---|
| Verify pipeline | duration p95 | 9.30 s (mean 6.89, max 18.83) | <10 s WORKS | WORKS (sub) |
| Verify pipeline | failure rate excl. maintenance | 23.19% (118 fails / 427 runs; 96 stale, 22 drift, transient share 16.1%) | >10% BROKEN | **BROKEN** |
| Timer cadence | duration share of cadence | 6.89 s / 1803 s = 0.38% | <25% WORKS | WORKS (sub) |
| Timer cadence | host-awake run coverage | naive 427/670.9 slots = 63.6%; awake denominator not collected | ≥90% of slots required | **UNKNOWN** |
| Watcher | journal volume | 105.9 KB/day (1,482,631 B / 14 d; peak 2026-09-14, 2514 lines) | 100–500 KB/day DEGRADED | DEGRADED (sub) |
| Watcher | RSS stability | Δ 0 kB (RSS 2168 kB) | <10 MB/h | WORKS (sub) |
| Watcher | suspect-write err-class | 4925 lines, 0 unexplained (all map to Sep 13–15 rebuild/reapply events) | 0 unexplained required | WORKS (sub) |
| Regression corpus | harness wall time | 9.45 s, 28/28 pass, 28/28 kill-proved | <5 min WORKS | WORKS (sub) |
| Regression corpus | pair health | 0 NON-ACTIVE-anchored; **11 ORPHAN** | 0 ORPHAN required | DEGRADED (sub) |
| Registry | unjustified false-backlog >30 d | 0 (5 false-entries, ages 41/1/16/40/20 d, all justified) | 0 required | WORKS |
| Registry | stale_claim_count | 0 | 0 required | WORKS |
| Alert delivery | fires per day | 11.06 observed-span (naive 5.29) | >1/day BROKEN | **BROKEN** |
| Alert signal | false_positive_share | 27.0% (20/74) | 20–50% DEGRADED | DEGRADED |
| Fork/binary | tree on release tag | no — oc on `fix/tui-pin-directory-guard-v1.18.5` | release tag required | DEGRADED (trigger) |
| Fork/binary | dep_version misalignment | 1 (`opencode--sse-directory-filter-removal` @ 1.17.9-local vs live 1.18.5) | 0 required | DEGRADED (trigger) |

Full derivation per row: `analysis/verdict-matrix.md`. Context figures not fed into thresholds: alert latency p50 7 s / p95 13 s; CPU median 8.36 s per fire; no autoclear path; max marker staleness 135,226 s (37.6 h); registry doc_mismatch_count 3; surfaces_variant_count 7; 9 reapply events recorded with wall-time known for only 1 (the 2026-09-08 dist-destroy incident, ~2 h outage).

---

## 4. What works / what does not

Transcribed from the verdict matrix (the authoritative roll-up: WORKS 1 · DEGRADED 4 · BROKEN 2 · UNKNOWN 1).

**WORKS — Registry.** All 5 `runtime_effective:false` entries carry justifications; nothing sits unjustified past 30 days; no stale claims. The tracking discipline built after the 2026-07-13 loss of 8/9 patches is holding.

**DEGRADED — Watcher.** Memory-stable and fully attributed error bursts, but journal volume crept over the WORKS line (105.9 vs 100 KB/day), driven almost entirely by the 4,925-line OMO-dist-suspect burst during the Sep 13–14 rebuild — a real signal working correctly, just voluminous.

**DEGRADED — Regression corpus.** Fast and green, but 11 ORPHAN pairs guard repo plugins/configs with no patch anchor: the corpus has drifted broader than the registry it was built to mirror, and the README still claims 25 pairs against the actual 28.

**DEGRADED — Alert signal quality.** 27% of fires are false positives and markers never autoclear — the operator cannot trust an alert without checking it manually.

**DEGRADED — Fork/binary burden.** Both trees sit off their advertised anchors (oc on a fix branch; omo 12 commits past its tag), and 1 dep_version misalignment exists (acknowledged drift, not silent).

**BROKEN — Verify pipeline failure rate.** Duration passes; the failure signal does not. 96 of 118 failures are verify-stale findings — including artifacts of non-main worktree checkouts (a fresh run in a worktree produced 1 stale + 1 missing-target by itself) — so the red/green signal overstates real drift.

**BROKEN — Alert delivery volume.** 5–11 fires/day against a designed ≤1/week: the alert channel fires so often it trains the operator to ignore it.

**UNKNOWN — Timer cadence coverage.** Duration passes; coverage is unjudgeable without a host-awake denominator.

No defects were found in: watcher memory management (RSS Δ 0 kB), watcher error attribution (0 unexplained lines after mapping the burst to reapply events), registry justification discipline (5/5 justified), or corpus test correctness (28/28 pass + kill-proved). These positives are the calibration baseline — the stack's measurement core is sound; its signaling layer is what misleads.

---

## 5. Decision framework

One primary recommendation per evaluable component. The timer-cadence row is not defaulted to a verb — it is blocked on a missing metric.

### 5.1 Verify pipeline — **tune**

- **Why**: duration already WORKS (p95 9.30 s); the BROKEN verdict is entirely the 23.19% failure rate, dominated by 96 verify-stale findings inflated by worktree artifacts (task-1/verify-pipeline-metrics.json; a fresh worktree run yields 1 stale + 1 missing-target on its own).
- **Cost of tuning**: one focused change to `verify-live-patches.sh` (worktree-checkout awareness → report as SKIP-WORKTREE, not FAIL) plus a 7-day re-measure window. Roughly one agent-session of work plus a week of passive data.
- **Cost of doing nothing**: the 23.19% red rate keeps training everyone that red means nothing; real drift (22 genuine findings) drowns in 96 artifacts.
- **First task**: add non-main-worktree detection to the stale/missing-target classification path, re-run the 14-day journal attribution to show the projected rate under the new rule, then enable and re-measure against the <2% WORKS threshold.

### 5.2 Timer cadence — **decision blocked on metric**

- The threshold requires host-awake run coverage ≥90% of slots; no Wave-1 evidence collected a suspend/resume denominator, so the honest verdict is UNKNOWN, not a forced fail (`task-7/gaps-section.md`). The naive 63.6% cannot distinguish "host asleep" from "timer missing slots".
- **Missing metric**: per-14d host suspend/resume log intersected with the timer slot schedule.
- **Owning task**: a one-command collection (`journalctl` suspend-target audit) joined against the task-1 run timestamps — a small instrument-more task, deliberately not folded into a verdict here.
- **Cost of blocking**: one collection command. **Cost of skipping**: an UNKNOWN row that silently becomes a standing excuse whenever coverage is questioned.

### 5.3 Watcher — **keep**

- **Why**: the only degraded sub-metric is journal volume at 105.9 KB/day, six percent over the line, driven by correctly-attributed rebuild bursts; RSS and err-class sub-verdicts are WORKS (task-2/watcher-metrics.json, task-6/reapply-events.tsv).
- **Cost of keeping**: zero changes; accept occasional DEGRADED readings during rebuild periods.
- **Cost of doing nothing**: if rebuild/reapply frequency rises, volume could climb the 100–500 KB/day band toward BROKEN (>500).
- **First task** (if acted on later): add day-level volume rollover/compression in the watcher's journal output before any rotation tuning.

### 5.4 Regression corpus — **consolidate**

- **Why**: 11 of 28 pairs are ORPHAN — they guard repo plugins/configs with no `.sisyphus/patches/*.md` anchor, so the corpus no longer mirrors the registry it tracks (task-3/pair-value-map.tsv). Runtime and correctness are fine (9.45 s, 28/28, all kill-proved), so this is a scope problem, not a quality one.
- **Cost of consolidating**: a classification pass over the 11 ORPHAN pairs — retire true orphans, promote genuinely valuable guards to an explicit INFRA/GUARD class — plus fixing the README count claim (25 → 28). One agent-session.
- **Cost of doing nothing**: the corpus keeps growing past the registry; every future "is this test still earning its slot?" audit re-pays the mapping cost; README drift (already counted in the 3 doc mismatches) compounds.
- **First task**: decide retire-vs-reclassify per ORPHAN pair from the task-3 mapping table, starting with the five review-enforcer pairs (014/015/016/018/019).

### 5.5 Registry — **instrument-more**

- **Why**: the only WORKS component, and the goal is to keep it that way while closing its residual blind spots: doc_mismatch_count 3 (one entry absent from `docs/patches.md`; README claims 23 active vs actual 28 and 25 corpus pairs vs actual 28) and silent_skip_risk (non-active entries skip schema checks entirely — task-4/registry-health.json).
- **Cost**: a periodic justification-audit job (exists as manual check today) plus a doc-sync diff check. Small, scriptable.
- **Cost of doing nothing**: WORKS decays quietly — the silent-skip path means a malformed future entry would evade verification without any signal, which is precisely the 2026-07-13 failure shape.
- **First task**: add a `--schema-all` mode to the patch-entry schema test so non-active entries get structural checks too.

### 5.6 Alert delivery — **keep**

- **Why**: the delivery channel itself is mechanically sound — fires land (latency p50 7 s), each fire re-verifies serially (CPU median 8.36 s), and the hermetic sandbox exercise proved the guard logic correct (task-5/alert-path-metrics.json, task-5/sandbox-run.log). The BROKEN verdict is volume, and the volume is manufactured by the false positives owned by 5.7 — replacing the channel would not fix that.
- **Cost of keeping**: none beyond the 5.7 work; volume falls as false positives fall.
- **Cost of doing nothing**: 5–11 fires/day continue until suppression lands; each costs ~8 s CPU and one unit of operator trust.
- **First task**: none for delivery itself — track volume as the success metric of the 5.7 tune.

### 5.7 Alert signal quality — **tune**

- **Why**: false_positive_share 27.0% (20/74) sits mid-band, no autoclear exists, and the worst stale window spanned 37.6 h across 68 green runs (task-5/alert-path-metrics.json). Suppression of near-commit and next-run-green fires, plus an autoclear on the first green run after a failure, addresses all three.
- **Cost**: edits to `scripts/integrity-alert.sh` (suppress ±35-min-commit fires; autoclear marker on first green) plus one sandbox re-verification — the sandbox harness from task-5 already exists and is reusable.
- **Cost of doing nothing**: delivery stays BROKEN (the 11.06/day rate is mostly these false positives), and the operator keeps paying manual verification on ~1 in 4 alerts indefinitely.
- **First task**: implement marker autoclear-on-green (smallest change, kills the 37.6 h staleness class), then layer the near-commit suppression rule and re-measure fires/day over 7 days against the ≤1/week WORKS threshold.

### 5.8 Fork/binary burden — **tune**

- **Why**: both DEGRADED triggers are present and both are cheap to clear — oc tree parked on `fix/tui-pin-directory-guard-v1.18.5` instead of a release tag, and 1 dep_version misalignment (`opencode--sse-directory-filter-removal` @ 1.17.9-local, acknowledged drift) (task-6/maintenance-burden.json).
- **Cost**: re-anchor the oc tree on the v1.18.5 release tag (verify no dirty-file loss first — 2 dirty files recorded) and either bump the drifted patch's dep_version or re-confirm its `runtime_effective:false` justification. Under an hour of careful work.
- **Cost of doing nothing**: the tree stays one careless `git checkout`/rebuild away from losing unanchored work — the exact mechanism of the 2026-09-08 dist-destroy incident (~2 h outage) and the 2026-07-13 silent loss of 8/9 patches (task-6/reapply-events.tsv). Effort was never recorded for 8 of 9 reapply events, so the true standing cost is unmeasured but recurring.
- **First task**: tag-verify the oc tree against v1.18.5, stash/commit the 2 dirty files, resolve the sse-directory-filter-removal dep_version entry.

### 5.9 Scope note

The AGENTS.md reference to the regression corpus ("paired `.sh` + `.kill.sh` tests for every bug ever fixed", AGENTS.md:217/229) is instruction-file scope — it states a process requirement, not a count claim — and is excluded from the doc-mismatch census per plan. The corpus count drift lives in README.md:78 ("25 pairs" vs measured 28) and is covered by 5.4 and the registry's doc-mismatch count of 3.

---

## 6. Evidence index

All paths relative to repo root.

- .sisyphus/evidence/perf-review-patch-preservation/analysis/verdict-matrix.md
- .sisyphus/evidence/perf-review-patch-preservation/task-1/verify-pipeline-metrics.json
- .sisyphus/evidence/perf-review-patch-preservation/task-1/journal-extraction.log
- .sisyphus/evidence/perf-review-patch-preservation/task-1/fresh-timing-and-error-path.log
- .sisyphus/evidence/perf-review-patch-preservation/task-2/watcher-metrics.json
- .sisyphus/evidence/perf-review-patch-preservation/task-2/watcher-journal-14d.log
- .sisyphus/evidence/perf-review-patch-preservation/task-2/class-breakdown.tsv
- .sisyphus/evidence/perf-review-patch-preservation/task-3/harness-total-wall.log
- .sisyphus/evidence/perf-review-patch-preservation/task-3/pair-value-map.tsv
- .sisyphus/evidence/perf-review-patch-preservation/task-3/corpus-timing.tsv
- .sisyphus/evidence/perf-review-patch-preservation/task-4/registry-health.json
- .sisyphus/evidence/perf-review-patch-preservation/task-4/registry-inventory.tsv
- .sisyphus/evidence/perf-review-patch-preservation/task-4/false-backlog.tsv
- .sisyphus/evidence/perf-review-patch-preservation/task-4/doc-mismatches.txt
- .sisyphus/evidence/perf-review-patch-preservation/task-5/alert-path-metrics.json
- .sisyphus/evidence/perf-review-patch-preservation/task-5/alert-journal-14d.log
- .sisyphus/evidence/perf-review-patch-preservation/task-5/sandbox-run.log
- .sisyphus/evidence/perf-review-patch-preservation/task-6/maintenance-burden.json
- .sisyphus/evidence/perf-review-patch-preservation/task-6/reapply-events.tsv
- .sisyphus/evidence/perf-review-patch-preservation/task-6/tree-state.log
- .sisyphus/evidence/perf-review-patch-preservation/task-7/consistency-check.log
- .sisyphus/evidence/perf-review-patch-preservation/task-7/gaps-section.md

*No action required from this report by itself — each recommendation in section 5 is priced for a follow-up plan the operator has not yet approved.*
