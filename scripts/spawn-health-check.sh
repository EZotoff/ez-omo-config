#!/usr/bin/env bash
#
# spawn-health-check.sh — zero-token spawn probe + respawn-once gate (W3.3)
#
# Plan: .omo/plans/workflow-standardization.md §W3 TODO item 13.
#
# Usage:
#   spawn-health-check.sh <session_id> [--probe-window N] [--db FILE]
#   spawn-health-check.sh --respawn-record --session X --max N [--state-file F]
#
# Probe mode: read-only opencode.db query (sqlite3 mode=ro URI — the DB is
# NEVER written, opened read-only at the URI level). Prints ONE parseable
# JSON line:
#   {session_id, exists, message_count, minutes_since_spawn,
#    verdict: healthy|zero_token|spawning|unknown}
#
#   healthy    — exists, message_count >= 1
#   zero_token — exists, 0 messages, older than --probe-window (default 10m)
#   spawning   — exists, 0 messages, younger than the window (still warming up)
#   unknown    — no such session row
#
# ALWAYS-JSON contract (probe mode): exactly one parseable JSON line on stdout
# and exit 0 in EVERY case — missing DB, invalid --probe-window, SQL errors,
# unknown session all yield {verdict: "unknown", error: "<why>"} plus exit 0.
# The verdict/error fields carry the signal; the exit code never does.
#
# Respawn-record mode (--respawn-record): the mechanical respawn-once gate.
# The orchestrator MUST call this BEFORE respawning a zero_token child.
# Appends {session_id, respawn_n, ts} to the state file (default
# .omo/respawn-state.jsonl; flock-serialized) and prints one JSON line:
#   {respawn_allowed: true|false, respawn_n: N}
# respawn_allowed=false when respawn_n would exceed --max N — the refusal
# itself IS the alert: first refusal means respawn budget exhausted →
# escalate to the operator (second refusal = escalate). Exit 0 always.
#
# Dependencies: bash >= 4.3, python3, jq, flock. No network, no ports.

set -euo pipefail

DB="${HOME}/.local/share/opencode/opencode.db"
WINDOW=10
SID=""
STATE_FILE=".omo/respawn-state.jsonl"
RESPAWN_MODE=false
RSESSION=""
RMAX=""

unknown_json() { # session error -> one parseable JSON line, verdict unknown
    python3 -c 'import json,sys; print(json.dumps({"session_id": sys.argv[1] or None, "exists": False, "message_count": 0, "minutes_since_spawn": None, "verdict": "unknown", "error": sys.argv[2]}))' "${1:-}" "$2"
}

if [[ "${1:-}" == "--respawn-record" ]]; then
    RESPAWN_MODE=true
    shift
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --session) RSESSION="${2:?}"; shift 2 ;;
            --max) RMAX="${2:?}"; shift 2 ;;
            --state-file) STATE_FILE="${2:?}"; shift 2 ;;
            *) echo "usage error: unknown flag $1 (respawn-record mode: --session X --max N [--state-file F])" >&2; exit 0 ;;
        esac
    done
    if [[ -z "$RSESSION" || -z "$RMAX" ]] || ! [[ "$RMAX" =~ ^[0-9]+$ ]]; then
        echo "usage error: --respawn-record requires --session X and integer --max N" >&2
        exit 0
    fi

    mkdir -p "$(dirname "$STATE_FILE")"
    exec 8>"$STATE_FILE.lock"
    flock 8
    n=0
    if [[ -s "$STATE_FILE" ]]; then
        n="$(jq -r --arg s "$RSESSION" 'select(.session_id == $s) | .respawn_n' "$STATE_FILE" 2>/dev/null | grep -E '^[0-9]+$' | tail -n 1 || true)"
        [[ -n "$n" ]] || n=0
    fi
    if (( n >= RMAX )); then
        # Refusal IS the alert: respawn budget exhausted -> orchestrator escalates.
        jq -c -n --argjson n "$n" '{respawn_allowed: false, respawn_n: $n}'
    else
        new=$((n + 1))
        printf '{"session_id":"%s","respawn_n":%d,"ts":"%s"}\n' \
            "$RSESSION" "$new" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$STATE_FILE"
        jq -c -n --argjson n "$new" '{respawn_allowed: true, respawn_n: $n}'
    fi
    exec 8>&-
    exit 0
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        --probe-window) [[ $# -ge 2 ]] || { unknown_json "$SID" "usage: --probe-window requires a value"; exit 0; }; WINDOW="$2"; shift 2 ;;
        --db) [[ $# -ge 2 ]] || { unknown_json "$SID" "usage: --db requires a value"; exit 0; }; DB="$2"; shift 2 ;;
        --*) unknown_json "$SID" "usage: unknown flag $1"; exit 0 ;;
        *) [[ -z "$SID" ]] || { unknown_json "$SID" "usage: extra positional argument $1"; exit 0; }; SID="$1"; shift ;;
    esac
done

if [[ -z "$SID" ]]; then
    unknown_json "" "no session_id argument given"
    exit 0
fi
if ! [[ "$WINDOW" =~ ^[0-9]+$ ]]; then
    unknown_json "$SID" "invalid --probe-window (must be a non-negative integer minutes value, got: $WINDOW)"
    exit 0
fi
if [[ ! -f "$DB" ]]; then
    unknown_json "$SID" "db not found: $DB"
    exit 0
fi

# All DB access below is mode=ro URI — read-only, LIMIT-bounded.
# The python body catches every failure path (SQL or otherwise) and still
# prints exactly one parseable JSON line.
python3 - "$DB" "$SID" "$WINDOW" <<'PYEOF' || unknown_json "$SID" "probe failed (sql or io error)"
import json, sqlite3, sys

db_path, sid, window = sys.argv[1], sys.argv[2], int(sys.argv[3])
out = {"session_id": sid, "exists": False, "message_count": 0,
       "minutes_since_spawn": None, "verdict": "unknown"}

try:
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
except Exception as e:
    out["error"] = f"sql error: {e}"
    print(json.dumps(out))
    sys.exit(0)

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
