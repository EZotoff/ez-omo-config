#!/usr/bin/env bash
#
# spawn-health-check.sh — zero-token spawn probe (W3.3)
#
# Plan: .omo/plans/workflow-standardization.md §W3 TODO item 13.
#
# Usage: spawn-health-check.sh <session_id> [--probe-window N] [--db FILE]
#
# Read-only opencode.db query (sqlite3 mode=ro URI — the DB is NEVER
# written, opened read-only at the URI level). Prints one JSON line:
#   {session_id, exists, message_count, minutes_since_spawn,
#    verdict: healthy|zero_token|spawning|unknown}
#
#   healthy    — exists, message_count >= 1
#   zero_token — exists, 0 messages, older than --probe-window (default 10m)
#   spawning   — exists, 0 messages, younger than the window (still warming up)
#   unknown    — no such session row
#
# Exit 0 ALWAYS (it is a probe; verdict carries the signal). This tool makes
# NO respawn decisions. Orchestrator policy: a zero_token verdict triggers
# respawn ONCE, then escalation/alert — never a respawn loop.
#
# Dependencies: bash >= 4.3, python3. No network, no ports.

set -euo pipefail

DB="${HOME}/.local/share/opencode/opencode.db"
WINDOW=10
SID=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --probe-window) WINDOW="${2:?}"; shift 2 ;;
        --db) DB="${2:?}"; shift 2 ;;
        --*) echo "usage error: unknown flag $1" >&2; exit 0 ;;
        *) [[ -z "$SID" ]] || { echo "usage error: extra arg $1" >&2; exit 0; }; SID="$1"; shift ;;
    esac
done
[[ -n "$SID" ]] || { echo '{"session_id":null,"exists":false,"message_count":0,"minutes_since_spawn":null,"verdict":"unknown"}'; exit 0; }
[[ -f "$DB" ]] || { echo "error: db not found: $DB" >&2; exit 0; }

# All DB access below is mode=ro URI — read-only, LIMIT-bounded.
python3 - "$DB" "$SID" "$WINDOW" <<'PYEOF'
import json, sqlite3, sys

db_path, sid, window = sys.argv[1], sys.argv[2], int(sys.argv[3])
out = {"session_id": sid, "exists": False, "message_count": 0,
       "minutes_since_spawn": None, "verdict": "unknown"}

con = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
try:
    row = con.execute(
        "select time_created from session where id = ? limit 1", (sid,)
    ).fetchone()
    if row is None:
        print(json.dumps(out))
        sys.exit(0)
    created_ms = row[0]
    mc = con.execute(
        "select count(*) from message where session_id = ? limit 1", (sid,)
    ).fetchone()[0]
finally:
    con.close()

import time
minutes = max(0, (time.time() * 1000 - created_ms) / 60000.0)
out["exists"] = True
out["message_count"] = mc
out["minutes_since_spawn"] = round(minutes, 1)
if mc >= 1:
    out["verdict"] = "healthy"
elif minutes > window:
    out["verdict"] = "zero_token"
else:
    out["verdict"] = "spawning"
print(json.dumps(out))
PYEOF
exit 0
