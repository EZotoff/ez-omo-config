#!/usr/bin/env bash
# Kill-proof for continuation-dedup-window.sh.
#
# Copies the script under test, sed-reverts the dedup window default to 180s,
# and re-runs the same scenario. With a 180s window a 5-minute-old marker is
# stale, so the second run MUST re-POST (total 2) — proving the regression test
# detects the narrow-window bug it guards.
set -uo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/helpers.sh"

REAL_SCRIPT="$(cd "$(dirname "$0")/../.." && pwd)/scripts/restart-with-continuation.sh"
REAL_HOME="$HOME"
UNIT="reg-dedup.service"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

SCRATCH="$(mktemp -d "${REAL_HOME:-$HOME}/.cache/cont-dedup-kill.XXXXXX")"
export SCRATCH
cleanup() { rm -rf "$SCRATCH"; }
trap cleanup EXIT

BUGGED="$SCRATCH/restart-with-continuation-bugged.sh"
sed 's/^RESUME_DEDUP_WINDOW="${RESUME_DEDUP_WINDOW:-1800}"$/RESUME_DEDUP_WINDOW="${RESUME_DEDUP_WINDOW:-180}"/' \
  "$REAL_SCRIPT" > "$BUGGED"
if ! grep -q 'RESUME_DEDUP_WINDOW:-180}' "$BUGGED"; then
  bad "sed did not revert the dedup window default in the bugged copy"
  echo "kill-proof: $PASS passed | $FAIL failed"; exit 1
fi

export PYBIN="$(command -v python3)"
export HOME="$SCRATCH/home"
export XDG_STATE_DIR="$SCRATCH/state"
STATE_DIR="$XDG_STATE_DIR/restart-continuations"
mkdir -p "$HOME/.local/share/opencode" "$STATE_DIR"
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
export STUB_LOG="$SCRATCH/stub.log"; : > "$STUB_LOG"
mkdir -p "$SCRATCH/bin"
cat > "$SCRATCH/bin/curl" <<STUB_EOF
#!$PYBIN
import json, os, sys
from urllib.parse import urlparse, parse_qs, unquote
LOG = os.path.join(os.environ["SCRATCH"], "stub.log")
def event(line):
    with open(LOG, "a") as f:
        f.write(line + "\n")
args = sys.argv[1:]
method = "GET"
if "-X" in args:
    method = args[args.index("-X") + 1]
p = urlparse(args[-1]); q = parse_qs(p.query)
if method == "GET" and p.path == "/session/status":
    event("probe"); print("{}"); sys.exit(0)
if method == "GET" and p.path == "/session":
    print(json.dumps([{"id": "sess-1", "title": "T1", "directory": unquote(q.get("directory", [""])[0]),
                       "parentID": None, "time": {"updated": 1000}}])); sys.exit(0)
if method == "POST" and p.path.endswith("/prompt_async"):
    event("post:" + p.path.split("/")[-2]); print("ok"); sys.exit(0)
event("UNHANDLED"); sys.exit(1)
STUB_EOF
chmod +x "$SCRATCH/bin/curl"
export PATH="$SCRATCH/bin:$PATH"

seed_snapshot() {
  printf '%s\n' '{"sessions":[{"id":"sess-1","title":"T1","directory":"'"$HOME"'/d1","status":"busy"}]}' \
    > "$STATE_DIR/snapshot-$UNIT-$1.json"
}

seed_snapshot 20261013-000000
bash "$BUGGED" hook-resume "$UNIT" "http://127.0.0.1:1" "$AUTH_ENV" > "$SCRATCH/out1.txt" 2>&1 || true
MARKER="$STATE_DIR/.resumed-win-sess-1"
touch -d '5 minutes ago' "$MARKER"
seed_snapshot 20261013-000100
bash "$BUGGED" hook-resume "$UNIT" "http://127.0.0.1:1" "$AUTH_ENV" > "$SCRATCH/out2.txt" 2>&1 || true
n="$(grep -c '^post:sess-1$' "$STUB_LOG" || true)"
if [[ "$n" == "2" ]]; then
  ok "bugged (180s) copy re-POSTs after a 5-min-old marker — test assertion is sensitive"
else
  bad "bugged copy did NOT re-POST (total POSTs=$n; expected 2) — kill-proof cannot detect the bug"
fi

echo "=========================================="
echo "continuation-dedup-window.kill: $PASS passed | $FAIL failed"
echo "=========================================="
[[ $FAIL -eq 0 ]]
