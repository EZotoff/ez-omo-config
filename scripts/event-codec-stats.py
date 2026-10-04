#!/usr/bin/env python3
"""Ladder helpers for the event-codec rollout (plan: event-log-write-amplification).

Modes:
  --sum rowsCompressed   total compressed rows across all daemon segments
                         (sum of per-(pid,startedAt) maxima — restart-safe,
                          monotonic while the codec keeps compressing)
  --sum decodeErrors     total decode errors ever (gate: must stay 0)
Reads ~/.local/share/opencode/event-codec-stats.jsonl (the codec's own stats).
"""
import argparse
import json
import os
import sys

STATS = os.path.expanduser("~/.local/share/opencode/event-codec-stats.jsonl")


def segment_maxima() -> dict[str, int]:
    if not os.path.exists(STATS):
        return {}
    maxima: dict[tuple, int] = {}
    with open(STATS) as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
            except json.JSONDecodeError:
                continue
            key = (entry.get("pid", 0), entry.get("startedAt", ""))
            value = int(entry.get("cumulative", {}).get(METRIC, 0))
            if value > maxima.get(key, 0):
                maxima[key] = value
    return maxima


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--sum", choices=["rowsCompressed", "decodeErrors"], required=True)
    args = parser.parse_args()
    METRIC = args.sum  # noqa: N816 — read by segment_maxima
    print(sum(segment_maxima().values()))
    sys.exit(0)
