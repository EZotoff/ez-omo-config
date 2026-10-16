#!/usr/bin/env python3
"""continuation-fp-report.py — false-positive accounting for restart-continuation nudges.

Classifies machine-injected continuation prompts (maintenance / wake / child) found in
the shared session DB and, for each, decides whether the nudge was a TRUE positive
(the latest prior assistant turn was still incomplete — work was genuinely interrupted)
or a FALSE positive (the prior turn had already completed — the agent will reply
"everything was done last turn").

This is the before/after measurement harness for the wave-A continuation fixes
(.omo/plans/continuation-fp-wave-a.md): run it before and after deployment, same
window, compare per-class precision.

Read-only: opens the session DB with mode=ro. Exits 0 on success.
"""
import argparse
import json
import os
import sqlite3
import sys
import time

NUDGE_LIKES = (
    ("%server was restarted for maintenance%", "maintenance"),
    ("%wake notification was lost%", "wake"),
    ("%background-task registry was lost%", "child"),
)

EXCLUDED_DIR_SUBSTRINGS = ("/tmp/", "session-learning")


def open_db():
    db = os.environ.get("CONTINUATION_DB_PATH") or os.path.expanduser(
        "~/.local/share/opencode/opencode.db"
    )
    return sqlite3.connect(f"file:{db}?mode=ro", uri=True)


def fetch_nudges(con, since_ms):
    clauses = " or ".join(
        "json_extract(p.data,'$.text') like ?" for _, _ in NUDGE_LIKES
    )
    rows = con.execute(
        f"""
        select p.session_id, p.time_created, json_extract(p.data,'$.text'),
               s.directory, s.title
        from part p join session s on s.id = p.session_id
        where p.time_created >= ? and ({clauses})
        order by p.time_created desc
        """,
        (since_ms, *[like for like, _ in NUDGE_LIKES]),
    ).fetchall()
    out = []
    for sid, tc, text, directory, title in rows:
        if any(sub in (directory or "") for sub in EXCLUDED_DIR_SUBSTRINGS):
            continue
        kind = next(k for like, k in NUDGE_LIKES if like.strip("%") in text)
        out.append({"session_id": sid, "at_ms": tc, "kind": kind,
                    "directory": directory, "title": title})
    return out


def classify(con, nudge):
    """FP = latest prior assistant message has time.completed (turn was done)."""
    row = con.execute(
        """
        select json_extract(data,'$.time.completed') from message
        where session_id = ? and json_extract(data,'$.role') = 'assistant'
          and time_created < ?
        order by time_created desc limit 1
        """,
        (nudge["session_id"], nudge["at_ms"]),
    ).fetchone()
    if row is None:
        return "unknown"  # no prior assistant turn — not classifiable
    return "fp" if row[0] else "tp"


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--days", type=float, default=7.0,
                    help="lookback window in days (default 7)")
    ap.add_argument("--json", action="store_true", help="machine-readable output")
    args = ap.parse_args()

    con = open_db()
    since_ms = (time.time() - args.days * 86400) * 1000
    nudges = fetch_nudges(con, since_ms)

    classes = ("maintenance", "wake", "child")
    stats = {k: {"nudges": 0, "fp": 0, "tp": 0, "unknown": 0} for k in classes}
    stats["total"] = {"nudges": 0, "fp": 0, "tp": 0, "unknown": 0}
    examples = []
    for n in nudges:
        verdict = classify(con, n)
        stats[n["kind"]]["nudges"] += 1
        stats[n["kind"]][verdict] += 1
        stats["total"]["nudges"] += 1
        stats["total"][verdict] += 1
        if verdict == "fp" and len(examples) < 10:
            examples.append({"at": time.strftime("%m-%d %H:%M", time.localtime(n["at_ms"] / 1000)),
                             "kind": n["kind"], "dir": n["directory"], "title": n["title"]})
    con.close()

    for k in (*classes, "total"):
        s = stats[k]
        decided = s["fp"] + s["tp"]
        s["precision_pct"] = round(100 * s["tp"] / decided, 1) if decided else None

    if args.json:
        print(json.dumps({"window_days": args.days, "generated_at": time.strftime("%Y-%m-%dT%H:%M:%S"),
                          "stats": stats, "fp_examples": examples}, indent=1))
    else:
        print(f"Restart-continuation nudge outcomes — last {args.days:g}d "
              f"(excludes /tmp + session-learning dirs)")
        print(f"{'class':<14}{'nudges':>7}{'FP':>6}{'TP':>6}{'unk':>5}{'precision':>11}")
        for k in (*classes, "total"):
            s = stats[k]
            prec = f"{s['precision_pct']:.1f}%" if s["precision_pct"] is not None else "-"
            print(f"{k:<14}{s['nudges']:>7}{s['fp']:>6}{s['tp']:>6}{s['unknown']:>5}{prec:>11}")
        if examples:
            print("\nSample false positives:")
            for e in examples:
                print(f"  {e['at']} {e['kind']:<12} {(e['dir'] or '')[:40]:40s} {(e['title'] or '')[:40]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
