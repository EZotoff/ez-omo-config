#!/usr/bin/env bash
# Regression: resume dedup window is 30 minutes (1800s), not 180s.
#
# Contract (plan: continuation-idle-kickstart-fix T2; 2026-10-13 incident): two
# restart instances 5 minutes apart both injected the same session because the
# 180s dedup window had already expired. The window must cover a restart burst
# plus its retry tail. A marker aged 5 minutes must still suppress a re-POST.
#
# Harness: scratch HOME (fake opencode.db), stub curl on PATH, real script via
# `hook-resume`. SCRIPT env override lets the paired .kill.sh point the SAME
# scenario at a copy with the default reverted to 180s.
set -uo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/helpers.sh"

SCRIPT="${SCRIPT:-$(cd "$(dirname "$0")/../.." && pwd)/scripts/restart-with-continuation.sh}"
REAL_HOME="$HOME"
UNIT="reg-dedup.service"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

SCRATCH="$(mktemp -d "${REAL_HOME:-$HOME}/.cache/cont-dedup.XXXXXX")"
export SCRATCH
cleanup() { rm -rf "$SCRATCH"; }
trap cleanup EXIT

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

seed_snapshot() { # seed_snapshot <stamp>
  printf '%s\n' '{"sessions":[{"id":"sess-1","title":"T1","directory":"'"$HOME"'/d1","status":"busy"}]}' \
    > "$STATE_DIR/snapshot-$UNIT-$1.json"
}

# Run 1: POST happens, marker written.
seed_snapshot 20261013-000000
bash "$SCRIPT" hook-resume "$UNIT" "http://127.0.0.1:1" "$AUTH_ENV" > "$SCRATCH/out1.txt" 2>&1 || true
n1="$(grep -c '^post:sess-1$' "$STUB_LOG" || true)"
MARKER="$STATE_DIR/.resumed-win-sess-1"
if [[ "$n1" == "1" && -e "$MARKER" ]]; then
  ok "run 1 POSTed once and wrote the dedup marker"
else
  bad "run 1 expected 1 POST + marker (posts=$n1 marker=$([[ -e $MARKER ]] && echo yes || echo no))"
fi

# Age the marker to 5 minutes ago (no sleep — mtime is faked).
touch -d '5 minutes ago' "$MARKER"

# Run 2: 5-min-old marker must still suppress the re-POST under the 1800s default.
seed_snapshot 20261013-000100
bash "$SCRIPT" hook-resume "$UNIT" "http://127.0.0.1:1" "$AUTH_ENV" > "$SCRATCH/out2.txt" 2>&1 || true
n2="$(grep -c '^post:sess-1$' "$STUB_LOG" || true)"
if [[ "$n2" == "1" ]]; then
  ok "5-min-old marker still dedups (total POSTs=1 under 1800s window)"
else
  bad "5-min-old marker did NOT dedup (total POSTs=$n2; expected 1)"
fi

echo "=========================================="
echo "continuation-dedup-window: $PASS passed | $FAIL failed"
echo "=========================================="
[[ $FAIL -eq 0 ]]
