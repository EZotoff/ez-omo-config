#!/usr/bin/env python3
"""Migrate gz1:-compressed event rows back to plain JSON (codec escape hatch).

REQUIRED before restarting ANY codec-less binary (including the pre-codec
backup) against a DB that contains gz1: rows — such binaries cannot decode
them and the event log would be unreadable.

Refuses to run while `opencode serve` processes are alive unless --force
(stop both systemd units first: systemctl --user stop opencode.service
opencode-interactive.service).

Modes:
  --make-fixtures N   rewrite N sampled plain rows into gz1: form (QA mode;
                      plain python3 gzip+base64 per the D1 envelope, no
                      patched binary needed). Intended for scratch copies.
  default             decompress ALL gz1: rows in-place, in batches, inside
                      transactions; prints wal_checkpoint guidance.
"""
from __future__ import annotations

import argparse
import base64
import gzip
import json
import os
import sqlite3
import subprocess
import sys

PREFIX = "gz1:"


def daemons_alive() -> bool:
    result = subprocess.run(["pgrep", "-f", "opencode serve"], capture_output=True, text=True)
    return result.returncode == 0


def fetch_compressed(con: sqlite3.Connection, limit: int, after_id: str | None) -> list[tuple[str, str]]:
    query = "SELECT id, data FROM event WHERE data LIKE 'gz1:%' AND id > ? ORDER BY id LIMIT ?"
    return con.execute(query, (after_id or "", limit)).fetchall()


def count_rows(con: sqlite3.Connection, pattern: str) -> int:
    return int(con.execute("SELECT COUNT(*) FROM event WHERE data LIKE ?", (pattern,)).fetchone()[0])


def make_fixtures(con: sqlite3.Connection, n: int) -> int:
    rows = con.execute(
        "SELECT id, data FROM event WHERE data NOT LIKE 'gz1:%' AND LENGTH(data) > 0 ORDER BY LENGTH(data) DESC LIMIT ?",
        (n,),
    ).fetchall()
    fixed = 0
    for row_id, data in rows:
        compressed = PREFIX + base64.b64encode(gzip.compress(data.encode())).decode()
        if len(compressed) >= len(data):
            continue  # don't grow rows; sample another
        con.execute("UPDATE event SET data = ? WHERE id = ?", (compressed, row_id))
        fixed += 1
    con.commit()
    return fixed


def migrate_out(con: sqlite3.Connection, batch: int) -> tuple[int, int]:
    migrated = failures = 0
    after_id: str | None = None
    while True:
        rows = fetch_compressed(con, batch, after_id)
        if not rows:
            break
        after_id = rows[-1][0]
        con.execute("BEGIN")
        try:
            for row_id, data in rows:
                try:
                    plain = gzip.decompress(base64.b64decode(data[len(PREFIX):])).decode()
                    json.loads(plain)  # must parse — guarantees we wrote valid JSON back
                except Exception as exc:
                    failures += 1
                    print(f"  UNDECODEABLE row {row_id}: {exc} — leaving compressed", file=sys.stderr)
                    continue
                con.execute("UPDATE event SET data = ? WHERE id = ?", (plain, row_id))
                migrated += 1
            con.commit()
        except Exception:
            con.rollback()
            raise
        print(f"  migrated {migrated} rows so far...")
    return migrated, failures


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db", default=os.path.expanduser("~/.local/share/opencode/opencode.db"))
    parser.add_argument("--batch", type=int, default=5000)
    parser.add_argument("--force", action="store_true", help="run even with live daemons (dangerous)")
    parser.add_argument("--make-fixtures", type=int, metavar="N", default=0, help="QA: compress N sampled plain rows")
    args = parser.parse_args()

    if not os.path.exists(args.db):
        print(f"no such db: {args.db}", file=sys.stderr)
        return 1
    if daemons_alive() and not args.force:
        print("live `opencode serve` detected — stop both units first:", file=sys.stderr)
        print("  systemctl --user stop opencode.service opencode-interactive.service", file=sys.stderr)
        print("or pass --force if you know better", file=sys.stderr)
        return 1

    con = sqlite3.connect(args.db, timeout=60)
    try:
        if args.make_fixtures:
            fixed = make_fixtures(con, args.make_fixtures)
            print(f"fixtures created: {fixed} rows now gz1:-compressed")
            return 0 if fixed > 0 else 1
        total = count_rows(con, "gz1:%")
        all_rows = count_rows(con, "%")
        print(f"rows total={all_rows}, compressed={total}")
        if total == 0:
            print("nothing to migrate — zero gz1: rows (already codec-clean)")
            return 0
        migrated, failures = migrate_out(con, args.batch)
        remaining = count_rows(con, "gz1:%")
        print(f"migrated={migrated} failures={failures} remaining_compressed={remaining}")
        print("checkpoint the WAL before restarting any binary:")
        print('  python3 -c "import sqlite3; sqlite3.connect(%r).execute(\'PRAGMA wal_checkpoint(TRUNCATE)\')' % args.db)
        return 0 if remaining == 0 and failures == 0 else 1
    finally:
        con.close()


if __name__ == "__main__":
    sys.exit(main())
