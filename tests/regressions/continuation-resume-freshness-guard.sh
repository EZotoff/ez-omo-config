#!/usr/bin/env bash
# Regression: top-level resume freshness guard (wave A T2, plan
# continuation-fp-wave-a.md).
#
# Contract: a top-level session captured busy whose turn COMPLETED during the
# restart gap (stub /session time.updated > snapshot captured_at_ms) must NOT
# be re-prompted — the same guard children/checkpoint/db_fallback paths already
# had. wake-pending entries are excluded (their guard is the union predicate).
# Fail-open on lookup failure.
set -uo pipefail

SCRIPT="${SCRIPT:-$(cd "$(dirname "$0")/../.." && pwd)/scripts/restart-with-continuation.sh}"
REAL_HOME="$HOME"
UNIT="reg-fresh.service"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

make_scratch() { # make_scratch <name> <stub_updated_ms>
  SCRATCH="$(mktemp -d "${REAL_HOME:-$HOME}/.cache/cont-fresh-${1}.XXXXXX")"
  export SCRATCH
  export PYBIN="$(command -v python3)"
  export HOME="$SCRATCH/home"
  export XDG_STATE_DIR="$SCRATCH/state"
  STATE_DIR="$XDG_STATE_DIR/restart-continuations"
  mkdir -p "$HOME/.local/share/opencode" "$STATE_DIR" "$HOME/d1"
  # DB drives discover_dirs only (no T1 wakes in this test)
  PYBIN="$PYBIN" HOME="$HOME" python3 - <<'DBEOF'
import os, sqlite3, time
db = os.path.join(os.environ["HOME"], ".local/share/opencode/opencode.db")
con = sqlite3.connect(db)
con.execute("create table session (id text primary key, directory text,"
            " time_updated real, time_archived real, parent_id text, title text)")
con.execute("insert into session values (?,?,?,?,?,?)",
            ("sess-1", os.path.join(os.environ["HOME"], "d1"),
             time.time() * 1000, None, None, "T1"))
con.commit()
DBEOF
  AUTH_ENV="$SCRATCH/auth.env"
  printf 'OPENCODE_SERVER_PASSWORD=testpass\n' > "$AUTH_ENV"
  export STUB_LOG="$SCRATCH/stub.log"
  : > "$STUB_LOG"
  export STUB_UPDATED_MS="$2"
  mkdir -p "$SCRATCH/bin"
  cat > "$SCRATCH/bin/curl" <<STUB_EOF
#!$PYBIN
import json, os, sys
from urllib.parse import urlparse, parse_qs, unquote
args = sys.argv[1:]
method = "GET"
if "-X" in args:
    method = args[args.index("-X") + 1]
p = urlparse(args[-1])
q = parse_qs(p.query)
if method == "GET" and p.path == "/session/status":
    print("{}"); sys.exit(0)
if method == "GET" and p.path == "/session":
    d = unquote(q.get("directory", [""])[0])
    print(json.dumps([{"id": "sess-1", "title": "T1", "directory": d,
                       "parentID": None,
                       "time": {"updated": int(os.environ["STUB_UPDATED_MS"])}}]))
    sys.exit(0)
if method == "POST" and p.path.endswith("/prompt_async"):
    with open(os.environ["STUB_LOG"], "a") as f:
        f.write("post:sess-1\n")
    print("ok"); sys.exit(0)
sys.exit(1)
STUB_EOF
  chmod +x "$SCRATCH/bin/curl"
  export PATH="$SCRATCH/bin:$PATH"
  # Stop snapshot: sess-1 captured busy at T0 (old); stub reports a NEWER updated.
  printf '%s\n' '{"sessions":[{"id":"sess-1","title":"T1","directory":"'"$HOME"'/d1","status":"busy","captured_at_ms":1700000000000}]}' \
    > "$STATE_DIR/snapshot-$UNIT-20261016-000000.json"
}
cleanup_scratch() { [[ -n "${SCRATCH:-}" ]] && rm -rf "$SCRATCH"; }

run_resume() { bash "$SCRIPT" hook-resume "$UNIT" "http://127.0.0.1:1" "$AUTH_ENV" > "$SCRATCH/out.txt" 2>&1; }

# --- A: turn completed during restart gap -> NO re-prompt --------------------
echo "--- A: session progressed after capture -> skip-stale, no post"
make_scratch a "$(( $(date +%s) * 1000 ))"   # stub updated = NOW >> captured 2023
run_resume
HOOKS_LOG="$XDG_STATE_DIR/restart-continuations/hooks.log"   # hook-mode resume output lands here
if ! grep -q '^post:sess-1$' "$STUB_LOG" && grep -q 'skip-stale sess-1' "$HOOKS_LOG"; then
  ok "progressed session skipped (skip-stale, no post)"
else
  bad "freshness guard missing: progressed session WAS re-prompted (log: $(tr '\n' '|' < "$HOOKS_LOG" | tail -c 200))"
fi
cleanup_scratch

# --- B: session still stale (turn really interrupted) -> re-prompted ---------
echo "--- B: session not progressed since capture -> post fires"
make_scratch b 1699999999000   # stub updated OLDER than captured_at_ms
run_resume
HOOKS_LOG="$XDG_STATE_DIR/restart-continuations/hooks.log"
if grep -q '^post:sess-1$' "$STUB_LOG"; then
  ok "genuinely stale session re-prompted"
else
  bad "guard over-fires: true interruption was NOT resumed (log: $(tr '\n' '|' < "$HOOKS_LOG" | tail -c 200))"
fi
cleanup_scratch

echo "regression: $PASS passed | $FAIL failed"
[[ "$FAIL" -eq 0 ]]
