#!/usr/bin/env python3
"""Event-bytes report — proves the event-data-compression patch's effect.

Reads the codec stats JSONL (~/.local/share/opencode/event-codec-stats.jsonl)
and the opencode DB (read-only) and emits:
  (a) event bytes/day by type (interval-delta per (pid, startedAt) segment,
      summed across daemon restarts)
  (b) compression ratio (raw vs stored bytes)
  (c) bytes-per-final-output-byte (event bytes/day ÷ assistant output bytes/day,
      via PartTable JOIN MessageTable filtered role='assistant')

Counters are cumulative-since-process-start; a segment's contribution over the
window is last-snapshot − first-snapshot inside the window. Daemon restarts
therefore never double-count (each segment accounted once).

Modes:
  default        report over --window hours (default 24)
  --selftest     hand-built 2-segment fixture (restart mid-window); asserts
                 the segment arithmetic; prints PASS/FAIL, exit code reflects
"""
from __future__ import annotations

import argparse
import json
import os
import sqlite3
import sys
import tempfile
import time
from dataclasses import dataclass, field

DEFAULT_STATS = os.path.expanduser("~/.local/share/opencode/event-codec-stats.jsonl")
DEFAULT_DB = os.path.expanduser("~/.local/share/opencode/opencode.db")


@dataclass
class Segment:
    pid: int
    started_at: str
    first: dict
    last: dict

    def delta(self, key: str) -> int:
        return int(self.last.get(key, 0)) - int(self.first.get(key, 0))


@dataclass
class Totals:
    raw: int = 0
    stored: int = 0
    compressed: int = 0
    plain: int = 0
    decode_errors: int = 0
    by_type: dict[str, dict[str, int]] = field(default_factory=dict)

    def add_segment(self, seg: Segment) -> None:
        for key, attr in (
            ("rawBytes", "raw"),
            ("storedBytes", "stored"),
            ("rowsCompressed", "compressed"),
            ("rowsPlain", "plain"),
            ("decodeErrors", "decode_errors"),
        ):
            setattr(self, attr, getattr(self, attr) + seg.delta(key))
        for etype, stats in seg.last.get("byType", {}).items():
            first_stats = seg.first.get("byType", {}).get(etype, {"rawBytes": 0, "rows": 0})
            cur = self.by_type.setdefault(etype, {"rawBytes": 0, "rows": 0})
            cur["rawBytes"] += int(stats.get("rawBytes", 0)) - int(first_stats.get("rawBytes", 0))
            cur["rows"] += int(stats.get("rows", 0)) - int(first_stats.get("rows", 0))


def load_segments(stats_path: str, window_seconds: float) -> list[Segment]:
    if not os.path.exists(stats_path):
        return []
    segments: dict[tuple[int, str], list[dict]] = {}
    cutoff = time.time() - window_seconds
    with open(stats_path) as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
            except json.JSONDecodeError:
                continue
            if entry.get("ts", "") < time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(cutoff)):
                continue
            key = (int(entry.get("pid", 0)), str(entry.get("startedAt", "")))
            segments.setdefault(key, []).append(entry)
    result = []
    for key, entries in segments.items():
        entries.sort(key=lambda e: e.get("ts", ""))
        result.append(Segment(pid=key[0], started_at=key[1], first=entries[0].get("cumulative", {}), last=entries[-1].get("cumulative", {})))
        result[-1].first.setdefault("byType", entries[0].get("byType", {}))
        result[-1].last.setdefault("byType", entries[-1].get("byType", {}))
    return result


def assistant_output_bytes(db_path: str, window_seconds: float) -> int:
    if not os.path.exists(db_path):
        return 0
    cutoff_ms = int((time.time() - window_seconds) * 1000)
    con = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True, timeout=10)
    try:
        row = con.execute(
            """
            SELECT COALESCE(SUM(LENGTH(p.data)), 0)
            FROM part p JOIN message m ON m.id = p.message_id AND m.session_id = p.session_id
            WHERE json_extract(m.data, '$.role') = 'assistant' AND m.time_updated >= ?
            """,
            (cutoff_ms,),
        ).fetchone()
        return int(row[0]) if row else 0
    finally:
        con.close()


def report(stats_path: str, db_path: str, window_hours: float) -> int:
    window_seconds = window_hours * 3600
    segments = load_segments(stats_path, window_seconds)
    totals = Totals()
    for seg in segments:
        totals.add_segment(seg)
    out_bytes = assistant_output_bytes(db_path, window_seconds)
    days = window_hours / 24 or 1

    print(f"window: {window_hours:.0f}h | segments: {len(segments)} (restarts: {max(0, len(segments) - 1)})")
    print(f"event raw bytes/day:      {totals.raw / days / 1e9:10.3f} GB")
    print(f"event stored bytes/day:   {totals.stored / days / 1e9:10.3f} GB")
    ratio = totals.raw / totals.stored if totals.stored else 0.0
    print(f"compression ratio:        {ratio:10.1f}x")
    print(f"rows compressed/plain:    {totals.compressed:10d} / {totals.plain}")
    print(f"decode errors:            {totals.decode_errors:10d}")
    if out_bytes:
        print(f"assistant output bytes:   {out_bytes / days / 1e9:10.3f} GB/day")
        print(f"bytes per output byte:    {totals.raw / days / max(1, out_bytes / days):10.1f}")
    print("top event types (raw bytes in window):")
    for etype, stats in sorted(totals.by_type.items(), key=lambda kv: -kv[1]["rawBytes"])[:8]:
        print(f"  {stats['rawBytes'] / days / 1e9:9.3f} GB/day  {stats['rows']:>8} rows  {etype}")
    if not segments:
        print("(no stats segments in window — counters read zero; expected pre-deploy)")
    return 0


def selftest() -> int:
    """Two (pid, startedAt) segments — a restart mid-window. Segment arithmetic
    must sum per-segment deltas, not double-count cumulative counters."""
    with tempfile.TemporaryDirectory(prefix="event-bytes-selftest-") as tmp:
        path = os.path.join(tmp, "stats.jsonl")
        now = time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime())
        rows = [
            {"ts": now, "pid": 1, "startedAt": "A", "cumulative": {"rawBytes": 0, "storedBytes": 0, "rowsCompressed": 0, "rowsPlain": 0, "decodeErrors": 0}, "byType": {"t.1": {"rawBytes": 0, "rows": 0}}},
            {"ts": now, "pid": 1, "startedAt": "A", "cumulative": {"rawBytes": 1000, "storedBytes": 100, "rowsCompressed": 5, "rowsPlain": 5, "decodeErrors": 0}, "byType": {"t.1": {"rawBytes": 1000, "rows": 10}}},
            # restart: cumulative counters reset
            {"ts": now, "pid": 2, "startedAt": "B", "cumulative": {"rawBytes": 0, "storedBytes": 0, "rowsCompressed": 0, "rowsPlain": 0, "decodeErrors": 0}, "byType": {}},
            {"ts": now, "pid": 2, "startedAt": "B", "cumulative": {"rawBytes": 500, "storedBytes": 50, "rowsCompressed": 2, "rowsPlain": 1, "decodeErrors": 1}, "byType": {"t.1": {"rawBytes": 300, "rows": 3}, "t.2": {"rawBytes": 200, "rows": 2}}},
        ]
        with open(path, "w") as fh:
            for row in rows:
                fh.write(json.dumps(row) + "\n")
        segments = load_segments(path, window_seconds=3600)
        totals = Totals()
        for seg in segments:
            totals.add_segment(seg)
        checks = [
            ("segments", len(segments), 2),
            ("raw", totals.raw, 1500),
            ("stored", totals.stored, 150),
            ("compressed", totals.compressed, 7),
            ("decode_errors", totals.decode_errors, 1),
            ("t.1 raw", totals.by_type.get("t.1", {}).get("rawBytes", 0), 1300),
            ("t.2 rows", totals.by_type.get("t.2", {}).get("rows", 0), 2),
        ]
        ok = True
        for name, got, want in checks:
            status = "ok" if got == want else "FAIL"
            ok = ok and got == want
            print(f"  {status}: {name} = {got} (want {want})")
        print("SELFTEST", "PASS" if ok else "FAIL")
        return 0 if ok else 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stats", default=DEFAULT_STATS)
    parser.add_argument("--db", default=DEFAULT_DB)
    parser.add_argument("--window", type=float, default=24.0, help="report window in hours")
    parser.add_argument("--selftest", action="store_true")
    args = parser.parse_args()
    if args.selftest:
        return selftest()
    return report(args.stats, args.db, args.window)


if __name__ == "__main__":
    sys.exit(main())
