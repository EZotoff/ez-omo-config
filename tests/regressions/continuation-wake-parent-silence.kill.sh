#!/usr/bin/env bash
# Kill-proof for continuation-wake-parent-silence.sh.
#
# Copies the script under test, sed-neuters the parent-silence predicate (the
# pre-wave-A behavior: every dispatched-awaiting-output wake re-kicks its
# parent), and re-runs scenario A against the copy. The bugged copy MUST
# re-kick the progressed parent (post:wake:sess-1 appears) — proving the
# regression test's assertion actually detects the missing guard.
set -uo pipefail

REAL_SCRIPT="$(cd "$(dirname "$0")/../.." && pwd)/scripts/restart-with-continuation.sh"
REAL_HOME="$HOME"
UNIT="reg-wsilence.service"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

SCRATCH="$(mktemp -d "${REAL_HOME:-$HOME}/.cache/cont-wsilence-kill.XXXXXX")"
export SCRATCH
cleanup() { rm -rf "$SCRATCH"; }
trap cleanup EXIT

# Bugged copy: neutralize the parent-silence check (always keep the wake).
BUGGED="$SCRATCH/restart-with-continuation-bugged.sh"
sed 's/if tu is not None and tu >= ab \* 1000:/if False:/' \
  "$REAL_SCRIPT" > "$BUGGED"
if ! grep -q 'if False:' "$BUGGED"; then
  bad "sed did not neuter the parent-silence predicate in the bugged copy"
  echo "kill-proof: $PASS passed | $FAIL failed"; exit 1
fi

export PYBIN="$(command -v python3)"
export HOME="$SCRATCH/home"
export XDG_STATE_DIR="$SCRATCH/state"
STATE_DIR="$XDG_STATE_DIR/restart-continuations"
mkdir -p "$HOME/.local/share/opencode" "$STATE_DIR"
NOW_MS="$(date +%s)000"
PARENT_TS="$NOW_MS" PYBIN="$PYBIN" HOME="$HOME" python3 - <<'DBEOF'
import os, sqlite3
db = os.path.join(os.environ["HOME"], ".local/share/opencode/opencode.db")
con = sqlite3.connect(db)
con.execute("create table session (id text primary key, directory text,"
            " time_updated real, time_archived real, parent_id text, title text)")
con.execute("insert into session values (?,?,?,?,?,?)",
            ("sess-1", os.path.join(os.environ["HOME"], "d1"),
             float(os.environ["PARENT_TS"]), None, None, "T1"))
con.commit()
DBEOF
AUTH_ENV="$SCRATCH/auth.env"
printf 'OPENCODE_SERVER_PASSWORD=testpass\n' > "$AUTH_ENV"
export STUB_LOG="$SCRATCH/stub.log"
: > "$STUB_LOG"
mkdir -p "$SCRATCH/bin"
cat > "$SCRATCH/bin/curl" <<STUB_EOF
#!$PYBIN
import json, os, sys
from urllib.parse import urlparse, parse_qs
args = sys.argv[1:]
method = "GET"
if "-X" in args:
    method = args[args.index("-X") + 1]
p = urlparse(args[-1])
if method == "GET" and p.path == "/session/status":
    print("{}"); sys.exit(0)
if method == "GET" and p.path == "/session":
    print(json.dumps([{"id": "sess-1", "title": "T1", "directory": "",
                       "parentID": None, "time": {"updated": 1000}}]))
    sys.exit(0)
if method == "POST" and p.path.endswith("/prompt_async"):
    with open(os.environ["STUB_LOG"], "a") as f:
        f.write("post:wake:sess-1\n")
    print("ok"); sys.exit(0)
sys.exit(1)
STUB_EOF
chmod +x "$SCRATCH/bin/curl"
export PATH="$SCRATCH/bin:$PATH"
mkdir -p "$HOME/d1/.omo/run-continuation/wakes"
: > "$STATE_DIR/snapshot-$UNIT-20261016-000000.json"
DISPATCH_MS="$(( $(date +%s) - 3600 ))000"
printf '%s\n' "{\"sessionID\":\"sess-1\",\"state\":\"dispatched-awaiting-output\",\"title\":\"W\",\"firstDispatchedAt\":$DISPATCH_MS}" \
  > "$HOME/d1/.omo/run-continuation/wakes/w-leak.json"

bash "$BUGGED" hook-resume "$UNIT" "http://127.0.0.1:1" "$AUTH_ENV" > "$SCRATCH/out.txt" 2>&1

if grep -q '^post:wake:sess-1$' "$STUB_LOG"; then
  ok "bugged copy (no predicate) re-kicks the progressed parent — kill-proof valid"
else
  bad "bugged copy did NOT re-kick; the regression cannot detect the bug"
fi

echo "kill-proof: $PASS passed | $FAIL failed"
[[ "$FAIL" -eq 0 ]]
