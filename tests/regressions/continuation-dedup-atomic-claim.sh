#!/usr/bin/env bash
# Regression: atomic dedup claim (wave A T3, plan continuation-fp-wave-a.md).
#
# Contract: the resume dedup marker must be claimed ATOMICALLY (O_CREAT|O_EXCL).
# Both OpenCode servers restart simultaneously and their hook-resume runs share
# one STATE_DIR; the old check-then-write let two racers both claim and POST —
# the 2026-10-16 measured bursts (same session nudged up to 12x in one minute).
# Two parallel hook-resume runs against the same snapshot MUST produce exactly
# ONE prompt POST.
set -uo pipefail

SCRIPT="${SCRIPT:-$(cd "$(dirname "$0")/../.." && pwd)/scripts/restart-with-continuation.sh}"
REAL_HOME="$HOME"
UNIT="reg-atom.service"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

SCRATCH="$(mktemp -d "${REAL_HOME:-$HOME}/.cache/cont-atom.XXXXXX")"
export SCRATCH
cleanup() { rm -rf "$SCRATCH"; }
trap cleanup EXIT

export PYBIN="$(command -v python3)"
export HOME="$SCRATCH/home"
export XDG_STATE_DIR="$SCRATCH/state"
STATE_DIR="$XDG_STATE_DIR/restart-continuations"
mkdir -p "$HOME/.local/share/opencode" "$STATE_DIR" "$HOME/d1" "$SCRATCH/bin"
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
cat > "$SCRATCH/bin/curl" <<STUB_EOF
#!$PYBIN
import json, os, sys, time
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
                       "parentID": None, "time": {"updated": 1000}}]))
    sys.exit(0)
if method == "POST" and p.path.endswith("/prompt_async"):
    time.sleep(1.5)   # hold the POST window open so the second racer overlaps
    with open(os.environ["STUB_LOG"], "a") as f:
        f.write("post:sess-1\n")
    print("ok"); sys.exit(0)
sys.exit(1)
STUB_EOF
chmod +x "$SCRATCH/bin/curl"
export PATH="$SCRATCH/bin:$PATH"
printf '%s\n' '{"sessions":[{"id":"sess-1","title":"T1","directory":"'"$HOME"'/d1","status":"busy","captured_at_ms":1700000000000}]}' \
  > "$STATE_DIR/snapshot-$UNIT-20261016-000000.json"
# warm the hook log pointer: each run appends to the shared hooks.log
rm -f "$STATE_DIR/hooks.log"

# Two simultaneous hook-resume runs (both servers' ExecStartPost, same STATE_DIR)
bash "$SCRIPT" hook-resume "$UNIT" "http://127.0.0.1:1" "$AUTH_ENV" > "$SCRATCH/out-a.txt" 2>&1 &
PA=$!
bash "$SCRIPT" hook-resume "$UNIT" "http://127.0.0.1:1" "$AUTH_ENV" > "$SCRATCH/out-b.txt" 2>&1 &
PB=$!
wait "$PA" "$PB"

POSTS="$(grep -c '^post:sess-1$' "$STUB_LOG" || true)"
if [[ "$POSTS" -eq 1 ]]; then
  ok "parallel hook-resume runs produced exactly ONE post (atomic claim holds)"
else
  bad "double injection: $POSTS posts under parallel claim race"
fi
if grep -q 'skip-dup sess-1' "$STATE_DIR/hooks.log"; then
  ok "loser logged skip-dup (claim rejected, not dropped)"
else
  bad "no skip-dup in hooks.log — race may have been luck, not the guard"
fi

echo "regression: $PASS passed | $FAIL failed"
[[ "$FAIL" -eq 0 ]]
