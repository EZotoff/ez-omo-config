#!/usr/bin/env bash
# Kill-proof for continuation-resume-freshness-guard.sh.
#
# Copies the script under test, sed-neuters the T2 top-level freshness guard
# (the pre-wave-A behavior: resume() had NO staleness check on top-level
# sessions), and re-runs scenario A. The bugged copy MUST re-prompt the
# progressed session — proving the regression detects the missing guard.
set -uo pipefail

REAL_SCRIPT="$(cd "$(dirname "$0")/../.." && pwd)/scripts/restart-with-continuation.sh"
REAL_HOME="$HOME"
UNIT="reg-fresh.service"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

SCRATCH="$(mktemp -d "${REAL_HOME:-$HOME}/.cache/cont-fresh-kill.XXXXXX")"
export SCRATCH
cleanup() { rm -rf "$SCRATCH"; }
trap cleanup EXIT

# Bugged copy: the T2 guard condition never fires.
BUGGED="$SCRATCH/restart-with-continuation-bugged.sh"
sed 's/if d and s.get("status") != "wake-pending":/if False:/' \
  "$REAL_SCRIPT" > "$BUGGED"
if ! grep -q 'if False:' "$BUGGED"; then
  bad "sed did not neuter the T2 guard in the bugged copy"
  echo "kill-proof: $PASS passed | $FAIL failed"; exit 1
fi

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
export STUB_UPDATED_MS="$(( $(date +%s) * 1000 ))"
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
printf '%s\n' '{"sessions":[{"id":"sess-1","title":"T1","directory":"'"$HOME"'/d1","status":"busy","captured_at_ms":1700000000000}]}' \
  > "$STATE_DIR/snapshot-$UNIT-20261016-000000.json"

bash "$BUGGED" hook-resume "$UNIT" "http://127.0.0.1:1" "$AUTH_ENV" > "$SCRATCH/out.txt" 2>&1

if grep -q '^post:sess-1$' "$STUB_LOG"; then
  ok "bugged copy (no guard) re-prompts the progressed session — kill-proof valid"
else
  bad "bugged copy did NOT re-prompt; the regression cannot detect the bug"
fi

echo "kill-proof: $PASS passed | $FAIL failed"
[[ "$FAIL" -eq 0 ]]
