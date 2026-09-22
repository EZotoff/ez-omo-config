#!/usr/bin/env python3
"""Sweep throwaway (probe-pattern) sessions out of the session picker.

Sets ``time_archived`` (soft-archive, reversible) on parentless sessions whose
titles match a strict throwaway allowlist. Soft-archived sessions disappear
from the TUI picker and ``session.list`` (which filters ``time_archived IS
NULL``) but remain fully intact in the DB — recoverable by clearing the
timestamp.

Why this exists (2026-09-21): the weekly 30-day retention archiver
(``opencode-session-archive.timer`` → ``opencode_maintenance.py archive``)
has never completed — its ``check_db_busy()`` treats open ``-wal``/``-shm``
sidecars as "busy", and the two always-on ``opencode serve`` instances hold
them open 24/7 (rc=10 in every logged run). Even a working 30-day prune
would not remove fresh probe debris. This script targets throwaway-pattern
sessions of any age, independent of the retention pipeline.

Safety model:
  * dry-run by default; ``--apply`` required to change anything
  * parentless sessions only (subagents never appear in the picker anyway)
  * strict title-regex allowlist built from observed junk (PROBE-OK,
    LB_OK, one-word reply tests, regression-test titles, ...)
  * skips sessions updated within ``--min-age-hours`` (default 12) so any
    in-flight campaign keeps its evidence
  * "New session - <timestamp>" and ``preflight-stdin:`` auto-titles are
    only matched for /tmp scratch cwds — a lazy auto-title on a real
    project session must never be swept
"""

from __future__ import annotations

import argparse
import os
import re
import sqlite3
import sys
from datetime import datetime, timedelta, timezone

DB_PATH = os.path.expanduser("~/.local/share/opencode/opencode.db")

EXIT_OK = 0
EXIT_ERROR = 1

# Patterns safe to match on ANY cwd (project-attached or scratch).
GLOBAL_TITLE_PATTERNS: tuple[re.Pattern[str], ...] = tuple(
    re.compile(p)
    for p in (
        r"^(GLM-SJ-|GLM-JUDGE-|OPENAI-|K3-)?PROBE-OK( probe| reply test)?$",
        r"^LB_OK",
        r"^Reply to ALL_GREEN status message$",
        r"^Model probe test( message)?$",
        r"^GLM-5\.3 probe (reply )?test( message)?$",
        r"^Probe request handling$",
        r"^OAuth probe request$",
        r"^Reply FINAL_OK confirmation$",
        r"^Exact-reply prompt test$",
        r"^[Pp]robe [Oo][Kk]$",
        r"^Probe echo test$",
        r"^Probe message title$",
        r"^Probe reply test$",
        r"^Quick acknowledgment message$",
        r"^Reply confirmation$",
        r"^Reply OK$",
        r"^Basic math question$",
        r"^12\*12 quick math question$",
        r"^Counting 1 to 50$",
        r"^(Bash tool |Bash tool timeout |Bash timeout )?[Rr]egression [Tt]est.*$",
        r"^Regression test: bash.*$",
    )
)

# Patterns only trusted for /tmp scratch cwds (auto-titles that could
# plausibly land on a real session in a project directory).
SCRATCH_ONLY_TITLE_PATTERNS: tuple[re.Pattern[str], ...] = tuple(
    re.compile(p)
    for p in (
        r"^New session - \d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}",
        r"^preflight-stdin:",
        r"^varprobe$",
    )
)


def is_scratch(directory: str | None) -> bool:
    return bool(directory) and bool(directory.startswith("/tmp/"))


def matches(title: str | None, directory: str | None) -> str | None:
    if not title:
        return None
    for pattern in GLOBAL_TITLE_PATTERNS:
        if pattern.search(title):
            return pattern.pattern
    if is_scratch(directory):
        for pattern in SCRATCH_ONLY_TITLE_PATTERNS:
            if pattern.search(title):
                return pattern.pattern
    return None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--apply",
        action="store_true",
        help="actually set time_archived (default: dry-run, list only)",
    )
    parser.add_argument(
        "--min-age-hours",
        type=float,
        default=12.0,
        help="skip sessions updated more recently than this (default: 12)",
    )
    parser.add_argument("--db", default=DB_PATH, help="path to opencode.db")
    args = parser.parse_args()

    if not os.path.exists(args.db):
        print(f"ERROR: database not found: {args.db}", file=sys.stderr)
        return EXIT_ERROR

    cutoff_ms = int(
        (datetime.now(timezone.utc) - timedelta(hours=args.min_age_hours)).timestamp()
        * 1000
    )
    now_ms = int(datetime.now(timezone.utc).timestamp() * 1000)

    conn = sqlite3.connect(args.db, timeout=30)
    conn.row_factory = sqlite3.Row
    rows = conn.execute(
        """
        SELECT id, title, directory, time_created, time_updated
        FROM session
        WHERE parent_id IS NULL
          AND time_archived IS NULL
          AND time_updated < ?
        ORDER BY time_updated ASC
        """,
        (cutoff_ms,),
    ).fetchall()

    candidates = []
    for row in rows:
        pattern = matches(row["title"], row["directory"])
        if pattern:
            candidates.append((row, pattern))

    mode = "APPLY" if args.apply else "DRY-RUN"
    print(f"{mode}: {len(candidates)} throwaway session(s) match "
          f"(scanned {len(rows)} parentless unarchived, min-age {args.min_age_hours}h)")
    for row, pattern in candidates:
        created = datetime.fromtimestamp(
            row["time_created"] / 1000, tz=timezone.utc
        ).strftime("%Y-%m-%d %H:%M")
        print(f"  {row['id']}  {created}  {(row['directory'] or '?')[:44]:44}  "
              f"{(row['title'] or '')[:44]:44}  ~ /{pattern}/")

    if not args.apply:
        print("dry-run only; re-run with --apply to soft-archive them")
        return EXIT_OK

    conn.execute("BEGIN")
    try:
        for row, _ in candidates:
            conn.execute(
                "UPDATE session SET time_archived = ? WHERE id = ? AND time_archived IS NULL",
                (now_ms, row["id"]),
            )
        conn.execute("COMMIT")
    except sqlite3.Error:
        conn.execute("ROLLBACK")
        raise
    finally:
        conn.close()

    print(f"soft-archived {len(candidates)} session(s) at {now_ms} "
          f"(recover: UPDATE session SET time_archived = NULL WHERE id = ...)")
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
