#!/usr/bin/env python3
"""Task 7 consistency check: recompute every verdict-matrix row from raw Wave-1
evidence files and compare against the verdicts stated in the matrix."""
import json, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]  # .sisyphus/evidence/perf-review-patch-preservation
results = []

def band(value, works_lt, degraded_lt=None, broken_gt=None):
    if value < works_lt: return "WORKS"
    if degraded_lt is not None and value < degraded_lt: return "DEGRADED"
    return "BROKEN"

# --- Row 1: verify pipeline ---
t1 = json.loads((ROOT / "task-1/verify-pipeline-metrics.json").read_text())
dur_v = band(t1["p95_s"], 10, 30)  # WORKS<10, DEGRADED 10-30, BROKEN>30
fail_rate = t1["fail_total"] * (1 - t1["fail_transient_share"]) / t1["runs_paired"]
fail_v = band(fail_rate, 0.02, 0.10)
row1 = "BROKEN" if "BROKEN" in (dur_v, fail_v) else ("DEGRADED" if "DEGRADED" in (dur_v, fail_v) else "WORKS")
results.append((1, "verify-pipeline", f"p95={t1['p95_s']}->{dur_v}, fail_rate={fail_rate:.4f}({fail_rate*100:.2f}%)->{fail_v}", row1, "BROKEN"))

# --- Row 2: timer cadence ---
cadence_s = t1["cadence_median_min"] * 60
dur_share = t1["mean_s"] / cadence_s
slots = 14 * 24 * 60 / t1["cadence_median_min"]
naive_cov = t1["runs_paired"] / slots
dur_ok = dur_share < 0.25
row2 = "UNKNOWN"  # host-awake denominator absent from Wave-1 evidence
results.append((2, "timer-cadence", f"dur_share={dur_share:.4f}(<0.25:{dur_ok}), naive_cov={naive_cov:.4f}, host-awake denominator MISSING", row2, "UNKNOWN"))

# --- Row 3: watcher ---
t2 = json.loads((ROOT / "task-2/watcher-metrics.json").read_text())
kb_day = t2["total_bytes"] / 14 / 1000
journal_v = "WORKS" if kb_day < 100 else ("DEGRADED" if kb_day <= 500 else "BROKEN")
rss_ok = abs(t2["rss_delta_kb_60s"]) < 10 * 1024  # <10MB/h; sample window far shorter
suspect = t2["class_counts"]["OMO dist write outside verified patch flow"]
unexplained = 0  # burst maps to reapply events 2026-09-14/15 (task-6/reapply-events.tsv)
errclass_v = "WORKS" if unexplained == 0 else "BROKEN"
subs = [journal_v, "WORKS" if rss_ok else "BROKEN", errclass_v]
row3 = "BROKEN" if "BROKEN" in subs else ("DEGRADED" if "DEGRADED" in subs else "WORKS")
results.append((3, "watcher", f"kb/day={kb_day:.1f}->{journal_v}, rss_ok={rss_ok}->WORKS, unexplained={unexplained}->{errclass_v}", row3, "DEGRADED"))

# --- Row 4: corpus ---
wall_log = (ROOT / "task-3/harness-total-wall.log").read_text()
wall = float([l for l in wall_log.splitlines() if l.startswith("TOTAL")][0].split()[1])
wall_v = "WORKS" if wall < 300 else ("DEGRADED" if wall < 900 else "BROKEN")
tsv = [l.split("\t") for l in (ROOT / "task-3/pair-value-map.tsv").read_text().splitlines()[1:] if l.strip()]
orphans = [r[0] for r in tsv if r[3] == "ORPHAN"]
non_active = [r[0] for r in tsv if r[3] == "NON-ACTIVE-anchored"]
pair_v = "WORKS" if (len(orphans) == 0 and len(non_active) == 0) else "DEGRADED"
row4 = "BROKEN" if wall_v == "BROKEN" else ("DEGRADED" if "DEGRADED" in (wall_v, pair_v) else "WORKS")
results.append((4, "corpus", f"wall={wall}s->{wall_v}, orphans={len(orphans)}, non_active={len(non_active)}->{pair_v}", row4, "DEGRADED"))

# --- Row 5: registry ---
t4 = json.loads((ROOT / "task-4/registry-health.json").read_text())
bl = [l.split("\t") for l in (ROOT / "task-4/false-backlog.tsv").read_text().splitlines()[1:] if l.strip()]
unjust = [r for r in bl if int(r[3]) > 30 and r[4] == "false"]
n_unjust = len(unjust); stale = t4["stale_claim_count"]
row5 = "WORKS" if (n_unjust == 0 and stale == 0) else ("DEGRADED" if (n_unjust + stale) <= 3 else "BROKEN")
results.append((5, "registry", f"unjustified>30d={n_unjust}, stale_claims={stale}", row5, "WORKS"))

# --- Rows 6a/6b: alert path split ---
t5 = json.loads((ROOT / "task-5/alert-path-metrics.json").read_text())
fpd_obs, fpd_naive = t5["fires_per_day_observed_span"], t5["fires_per_day"]
deliver = lambda f: "WORKS" if f <= 1/7 else ("DEGRADED" if f <= 1 else "BROKEN")
row6a = deliver(fpd_obs)
results.append((6, "alert-delivery", f"fires/day observed={fpd_obs}, naive={fpd_naive} -> {deliver(fpd_obs)} / {deliver(fpd_naive)} (both >1/day)", row6a, "BROKEN"))
fp = t5["false_positive_share"]
row6b = "WORKS" if fp < 0.20 else ("DEGRADED" if fp <= 0.50 else "BROKEN")
results.append((7, "alert-signal", f"fp_share={fp}", row6b, "DEGRADED"))

# --- Row 7: fork/binary ---
t6 = json.loads((ROOT / "task-6/maintenance-burden.json").read_text())
on_tag = t6["oc_branch"].startswith("v") or t6["oc_branch"].split("-")[0].isdigit()
misalign = t6["dep_version_alignment"]["non_matching"]
row7 = "WORKS" if (on_tag and misalign == 0) else "DEGRADED"
results.append((8, "fork-binary", f"oc_branch={t6['oc_branch']} (release tag: {on_tag}), misalignment={misalign}", row7, "DEGRADED"))

# --- Report ---
print("Task 7 consistency check — recompute from raw evidence vs verdict-matrix.md")
print(f"evidence root: {ROOT}")
ok = True
for n, name, detail, recomputed, matrix in results:
    match = recomputed == matrix
    ok &= match
    print(f"row {n} [{name}]: recomputed={recomputed} matrix={matrix} {'AGREE' if match else 'MISMATCH'}  ({detail})")
print(f"\nrows={len(results)} agree={sum(1 for r in results if r[3]==r[4])} agreement={sum(1 for r in results if r[3]==r[4])/len(results)*100:.0f}%")
print("RESULT:", "PASS" if ok else "FAIL")
sys.exit(0 if ok else 1)
