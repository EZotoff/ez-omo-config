# Gaps — UNKNOWN rows in verdict-matrix.md

## Row 2: Integrity-timer cadence — coverage dimension UNKNOWN

- Threshold requires "host-awake run coverage ≥ 90 % of slots".
- Wave-1 evidence (task-1/verify-pipeline-metrics.json) provides runs_paired=427, cadence_median=30.05 min, and confirms full 14 d journal retention — but contains **no host-awake/suspend denominator**.
- Naive 24/7-awake coverage = 427 / (20160 min / 30.05 min) = 427 / 670.9 = **63.6 %** (< 90 %). If the host suspends (laptop-style usage), the true awake-slot denominator shrinks and coverage rises; the journal alone cannot distinguish "host asleep" from "timer missed slots".
- Missing measurement to close the gap: per-14d host suspend/resume log (e.g. `journalctl -u suspend.target` / `systemd-inhibit` audit) intersected with the timer slot schedule. One command + a join against the task-1 run timestamps would resolve WORKS vs DEGRADED/BROKEN.
- The duration half of the cadence threshold IS evaluable and passes (0.38 % < 25 %); only the coverage half is UNKNOWN.

All other rows (1, 3, 4, 5, 6a, 6b, 7) have complete metrics and no UNKNOWN cells.
