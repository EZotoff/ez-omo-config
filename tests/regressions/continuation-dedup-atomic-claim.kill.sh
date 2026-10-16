#!/usr/bin/env bash
# Kill-proof for continuation-dedup-atomic-claim.sh.
#
# Copies the script under test, sed-strips O_EXCL from the claim (reverting to
# a non-exclusive create — the check-then-write race class), and re-runs the
# parallel scenario. The bugged copy MUST produce TWO posts — proving the
# regression actually detects the lost exclusivity.
set -uo pipefail

REAL_SCRIPT="$(cd "$(dirname "$0")/../.." && pwd)/scripts/restart-with-continuation.sh"
REAL_HOME="$HOME"
UNIT="reg-atom.service"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

SCRATCH="$(mktemp -d "${REAL_HOME:-$HOME}/.cache/cont-atom-kill.XXXXXX")"
export SCRATCH
cleanup() { rm -rf "$SCRATCH"; }
trap cleanup EXIT

# Bugged copy: strip exclusivity from every claim site.
BUGGED="$SCRATCH/restart-with-continuation-bugged.sh"
sed 's/os.O_CREAT | os.O_EXCL | os.O_WRONLY/os.O_CREAT | os.O_WRONLY/' \
  "$REAL_SCRIPT" > "$BUGGED"
if grep -q 'os.O_EXCL' "$BUGGED"; then
  bad "sed did not strip O_EXCL in the bugged copy"
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
cat > "$SCRATCH/bin/curl" <<STUB_EOF
#!$PYBIN
import json, os, sys, time
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
    time.sleep(1.5)
    with open(os.environ["STUB_LOG"], "a") as f:
        f.write("post:sess-1\n")
    print("ok"); sys.exit(0)
sys.exit(1)
STUB_EOF
chmod +x "$SCRATCH/bin/curl"
export PATH="$SCRATCH/bin:$PATH"
printf '%s\n' '{"sessions":[{"id":"sess-1","title":"T1","directory":"'"$HOME"'/d1","status":"busy","captured_at_ms":1700000000000}]}' \
  > "$STATE_DIR/snapshot-$UNIT-20261016-000000.json"

bash "$BUGGED" hook-resume "$UNIT" "http://127.0.0.1:1" "$AUTH_ENV" > "$SCRATCH/out-a.txt" 2>&1 &
PA=$!
bash "$BUGGED" hook-resume "$UNIT" "http://127.0.0.1:1" "$AUTH_ENV" > "$SCRATCH/out-b.txt" 2>&1 &
PB=$!
wait "$PA" "$PB"

POSTS="$(grep -c '^post:sess-1$' "$STUB_LOG" || true)"
if [[ "$POSTS" -ge 2 ]]; then
  ok "bugged copy (no O_EXCL) double-injects ($POSTS posts) — kill-proof valid"
else
  bad "bugged copy produced $POSTS post(s); the regression cannot detect the bug"
fi

echo "kill-proof: $PASS passed | $FAIL failed"
[[ "$FAIL" -eq 0 ]]
