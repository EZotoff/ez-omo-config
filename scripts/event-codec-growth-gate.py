#!/usr/bin/env python3
"""Growth gate for the event-codec rollout ladder (Task 18, plan: event-log-write-amplification).

Exit 0 iff the stored event-bytes/day over the trailing window is <= 20% of the
observe-mode baseline (4.38 GB/day, measured 2026-10-03 14:46-23:46, codec off,
heavy session traffic). Exit 1 otherwise. Uses the codec stats segments
(interval-delta accounting identical to scripts/event-bytes-report.py).
"""
import json
import os
import sys
import time

STATS = os.path.expanduser("~/.local/share/opencode/event-codec-stats.jsonl")
BASELINE_BYTES_PER_DAY = 4.38e9
TARGET_FRACTION = 0.20
# Codec enabled on the live daemons at 2026-10-04 09:26:16 +02:00 (07:26:16Z).
# Only segments from AFTER this instant count: the trailing window must never
# mix in observe-mode (codec-off) bytes, or the gate reads high by construction.
ENABLED_AT = "2026-10-04T07:26:16Z"


def main() -> int:
    if not os.path.exists(STATS):
        print("no stats file")
        return 1
    import datetime
    enabled = datetime.datetime.fromisoformat(ENABLED_AT.replace("Z", "+00:00")).timestamp()
    hours = max((time.time() - enabled) / 3600.0, 0.1)
    if hours < 2.0:
        print(f"insufficient post-enable window ({hours:.1f}h < 2h)")
        return 1
    segments: dict[tuple, list] = {}
    with open(STATS) as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
            except json.JSONDecodeError:
                continue
            if entry.get("startedAt", "") < ENABLED_AT:
                continue
            key = (entry.get("pid", 0), entry.get("startedAt", ""))
            segments.setdefault(key, []).append(entry)
    stored = 0
    for entries in segments.values():
        entries.sort(key=lambda e: e.get("ts", ""))
        first, last = entries[0], entries[-1]
        stored += int(last.get("cumulative", {}).get("storedBytes", 0)) - int(
            first.get("cumulative", {}).get("storedBytes", 0))
    per_day = stored / (hours / 24.0)
    budget = BASELINE_BYTES_PER_DAY * TARGET_FRACTION
    print(f"stored={stored/1e9:.3f} GB over {hours:.1f}h post-enable -> {per_day/1e9:.3f} GB/day (budget {budget/1e9:.3f})")
    ok = per_day <= budget
    print("GATE PASS" if ok else "GATE FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
