# Component Verdict Matrix — perf-review-patch-preservation (Task 7)

Applied the plan's threshold table (verbatim, no softening) to Wave-1 metrics (tasks 1–6).
All VALUE cells cite evidence files relative to `.sisyphus/evidence/perf-review-patch-preservation/`.
Section verdict = worst sub-threshold band. One UNKNOWN row exists → see `task-7/gaps-section.md`.

| # | COMPONENT | METRIC | VALUE (evidence file) | THRESHOLD | VERDICT | CONFIDENCE |
|---|-----------|--------|----------------------|-----------|----------|------------|
| 1 | Verify pipeline | verify duration p95 + failure rate excl. maintenance | p95 = 9.30 s; fail rate = 118 × (1 − 0.161) / 427 = **23.19 %** (task-1/verify-pipeline-metrics.json) | duration: WORKS < 10 s · DEGRADED 10–30 s · BROKEN > 30 s; fail rate: WORKS < 2 % · DEGRADED 2–10 % · BROKEN > 10 % | **BROKEN** | HIGH |
| 2 | Integrity-timer cadence | mean duration vs cadence + host-awake run coverage | duration share = 6.89 s / 1803 s = **0.38 %** ✓; coverage naive 427 / 670.9 slots = **63.6 %**, host-awake denominator NOT in Wave-1 evidence (task-1/verify-pipeline-metrics.json) | WORKS if mean duration < 25 % of cadence AND host-awake coverage ≥ 90 % of slots | **UNKNOWN** | MEDIUM |
| 3 | Watcher | journal volume/day + RSS stability + suspect-write err-class | 1,482,631 B / 14 d = **105,902 B/day ≈ 106 KB/day**; RSS Δ = **0 kB** (< 10 MB/h) ✓; suspect-class 4925 lines, **0 unexplained** (all map to 2026-09-13/14 rebuild + 2026-09-14/15 reapply events, task-6/reapply-events.tsv rows) (task-2/watcher-metrics.json; task-6/reapply-events.tsv) | journal: WORKS < 100 KB/day · DEGRADED 100–500 · BROKEN > 500; RSS Δ < 10 MB/h; err-class: WORKS = 0 unexplained | **DEGRADED** (journal size band 100–500 KB/day; RSS and err-class sub-verdicts WORKS) | HIGH |
| 4 | Regression corpus | harness wall time + pair health | wall = **9.45 s**, 28/28 pass, 28/28 kill-proved (task-3/harness-total-wall.log); 0 NON-ACTIVE-anchored ✓, **11 ORPHAN** (task-3/pair-value-map.tsv) | wall: WORKS < 5 min · DEGRADED 5–15 · BROKEN > 15; pair health: WORKS = 0 ORPHAN + 0 NON-ACTIVE-anchored, else DEGRADED with list | **DEGRADED** | HIGH |
| 5 | Registry | unjustified runtime_effective:false > 30 d + stale_claim_count | **0 unjustified** (5 false-entries ages {41,1,16,40,20} d, all justification_present=true, task-4/false-backlog.tsv); stale_claim_count = **0** (task-4/registry-health.json) | WORKS = 0 unjustified AND stale_claim_count = 0 · DEGRADED 1–3 · BROKEN > 3 | **WORKS** | HIGH |
| 6a | Alert path — delivery | fires per day | **11.06 / day** over observed 11-day span (naive /14 = 5.29) — both > 1/day (task-5/alert-path-metrics.json) | WORKS ≤ 1 fire/week · DEGRADED 1/day–1/week · BROKEN > 1/day | **BROKEN** | HIGH |
| 6b | Alert path — signal quality | false_positive_share | **0.2703** (20/74: 17 near-commit, 10 next-run-green, 7 overlap) (task-5/alert-path-metrics.json) | WORKS fp < 20 % · DEGRADED 20–50 % · BROKEN > 50 % | **DEGRADED** | HIGH |
| 7 | Fork + binary burden | oc tree on release tag + dep_version misalignment | oc branch = `fix/tui-pin-directory-guard-v1.18.5` (**not** a release tag); dep_version misalignment = **1** (`opencode--sse-directory-filter-removal` @ 1.17.9-local, runtime_effective:false → acknowledged drift) (task-6/maintenance-burden.json) | DEGRADED if oc tree not parked on a release tag OR dep_version misalignment > 0; WORKS otherwise | **DEGRADED** | HIGH |

## Section details

### 1. Verify pipeline — BROKEN
- Duration sub-verdict WORKS: p95 = 9.30 s (< 10 s), mean 6.89 s, max 18.83 s. Fresh-run median 13.54 s (worktree checkout; 1 stale + 1 missing-target expected there).
- Failure-rate sub-verdict BROKEN: 118 fails / 427 paired runs = 27.6 % raw; excluding the 16.1 % transient-maintenance share (commit within ±35 min or next run green within 1 h): 118 × (1 − 0.161) / 427 = **23.19 % > 10 % → BROKEN**. Attribution: 96 verify-stale (incl. missing-target), 22 drift, reconciliation delta 0 (task-1/verify-pipeline-metrics.json).

### 2. Integrity-timer cadence — UNKNOWN
- Duration condition met: mean 6.89 s = 0.38 % of the 30.05-min median cadence (< 25 %).
- Coverage condition NOT evaluable against its own definition: the threshold says "**host-awake** run coverage ≥ 90 % of slots", and Wave-1 evidence contains no host-awake/suspend data. The naive 24/7-awake figure is 427 / 670.9 slots = 63.6 % (< 90 %), which would fail — but it understates coverage on any host that suspends. Without an awake denominator the honest verdict is UNKNOWN, not a forced fail. See `task-7/gaps-section.md`.

### 3. Watcher — DEGRADED
- Journal volume: 1,482,631 B over 14 d = 105,902 B/day ≈ **106 KB/day** → falls in the 100–500 KB/day DEGRADED band (just over the 100 KB/day line; peak day 2026-09-14 = 2514 lines during the rebuild burst). Task-2's own `mb_per_week: 0.74` ≈ 105.7 KB/day — same band either way.
- RSS stability: Δ = 0 kB over the sample window (2168 kB RSS) — well within Δ < 10 MB/h. Sub-verdict WORKS.
- Suspect err-class: 4925 "OMO dist write outside verified patch flow" lines form the Sep 13–14 burst, which maps to the recorded 2026-09-14 OMO rebuild and 2026-09-15 dist-patch reapply events (task-6/reapply-events.tsv rows 8–9). Unexplained suspect lines = 0 → sub-verdict WORKS.
- Section verdict is the worst sub-band: DEGRADED (journal volume).

### 4. Regression corpus — DEGRADED
- Wall time WORKS: 9.45 s total, far under 5 min; 28/28 tests pass, 28/28 kill-tests prove, harness rc=0 (task-3/harness-total-wall.log).
- Pair health DEGRADED: 0 NON-ACTIVE-anchored ✓ but 11 ORPHAN pairs (task-3/pair-value-map.tsv). Required list:
  009-worktree-plan-bridge.sh · 010-git-safety-plugin-registered.sh · 011-git-safety-history-rewrite.sh · 014-review-enforcer-plan-lineage.sh · 015-review-enforcer-consultative-denylist.sh · 016-review-enforcer-abort-stub-degenerate.sh · 018-plugin-export-surface.sh · 019-review-critical-closeout.sh · 021-clipboard-display-env.sh · 022-worktree-create-tui-handoff.sh · 2026-08-02-subagent-near-empty-stall.sh
  These guard repo plugins/configs with no `.sisyphus/patches/*.md` anchor — corpus is broader than the registry (7 ACTIVE-anchored + 10 INFRA + 11 ORPHAN = 28).

### 5. Registry — WORKS
- 5 runtime_effective:false entries, ages {41, 1, 16, 40, 20} d, **all** justification_present=true (task-4/false-backlog.tsv) → 0 unjustified > 30 d.
- stale_claim_count = 0 (task-4/registry-health.json).
- Both WORKS conditions hold → WORKS. (Context, not a threshold input: doc_mismatch_count = 3, silent_skip_risk present — Task 8 territory.)

### 6. Alert path (split) — delivery BROKEN, signal quality DEGRADED
- Delivery: 74 fires in the observed span (journal horizon 2026-09-09 → 2026-09-16, 11 days) = 11.06 fires/day; the naive /14 figure 5.29/day is also > 1/day. Both readings land in **BROKEN** (> 1/day), so the horizon ambiguity does not change the verdict. Latency p50 7 s / p95 13 s, cpu median 8.36 s per fire.
- Signal quality: false_positive_share = 0.2703 (20/74) → 20–50 % band → **DEGRADED**. No autoclear path exists (`marker_autoclear_present: false`); max observed stale window 135,226 s (37.6 h across 68 green runs) — context for Task 8, not threshold input.

### 7. Fork + binary burden — DEGRADED
- oc tree parked on `fix/tui-pin-directory-guard-v1.18.5` — a fix branch, **not** a release tag → first DEGRADED trigger fires.
- dep_version misalignment = 1 > 0 (`opencode--sse-directory-filter-removal` @ 1.17.9-local vs live binary 1.18.5; runtime_effective:false → acknowledged drift, not silent) → second DEGRADED trigger fires.
- Either alone suffices for DEGRADED per the threshold; both present.

## Roll-up

WORKS: 1 (registry) · DEGRADED: 4 (watcher, corpus, alert-signal, fork/binary) · BROKEN: 2 (verify-pipeline, alert-delivery) · UNKNOWN: 1 (timer cadence coverage).

Matrix generated 2026-09-16 from Wave-1 evidence only; recomputation agreement: see `task-7/consistency-check.log`.
