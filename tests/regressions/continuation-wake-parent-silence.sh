#!/usr/bin/env bash
# Regression: union_wakes parent-silence predicate (wave A T1, plan
# continuation-fp-wave-a.md; Momus-approved units ab*1000).
#
# Contract: a dispatched-awaiting-output wake means the notification WAS
# dispatched — the union re-kicks the parent ONLY when the parent shows no turn
# activity since the wake's dispatch (session.time_updated < ab * 1000; ab is
# SECONDS, time_updated is MS). A parent that continued after dispatch (the OMO
# consumption-detection leak — 1170 such wakes as of 2026-10-16) must NOT be
# re-prompted. Fail-open: unreadable DB keeps the wake.
#
# Harness: scratch HOME (fake opencode.db drives discover_dirs + the T1 lookup),
# stub curl on PATH, real script via `hook-resume`. SCRIPT env override lets the
# paired .kill.sh point the SAME scenarios at a deliberately-bugged copy.
set -uo pipefail

SCRIPT="${SCRIPT:-$(cd "$(dirname "$0")/../.." && pwd)/scripts/restart-with-continuation.sh}"
REAL_HOME="$HOME"
UNIT="reg-wsilence.service"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

write_stub() { # write_stub <scratch>
  local s="$1"
  mkdir -p "$s/bin"
  cat > "$s/bin/curl" <<STUB_EOF
#!$PYBIN
import json, os, sys
from urllib.parse import urlparse, parse_qs, unquote
S = os.environ["SCRATCH"]
LOG = os.path.join(S, "stub.log")
def event(line):
    with open(LOG, "a") as f:
        f.write(line + "\n")
args = sys.argv[1:]
method = "GET"
if "-X" in args:
    method = args[args.index("-X") + 1]
url = args[-1]
p = urlparse(url)
q = parse_qs(p.query)
if method == "GET" and p.path == "/session/status" and not q:
    print("{}"); sys.exit(0)
if method == "GET" and p.path == "/session/status" and "directory" in q:
    print("{}"); sys.exit(0)
if method == "GET" and p.path == "/session":
    d = unquote(q.get("directory", [""])[0])
    # updated=1000 (ancient) -> the T2 freshness guard never fires here
    print(json.dumps([{"id": "sess-1", "title": "T1", "directory": d,
                       "parentID": None, "time": {"updated": 1000}}]))
    sys.exit(0)
if method == "POST" and p.path.endswith("/prompt_async"):
    sid = p.path.split("/")[-2]
    body = args[args.index("-d") + 1] if "-d" in args else ""
    tag = "wake" if "wake notification was lost" in body else "maint"
    event(f"post:{tag}:{sid}")
    print("ok"); sys.exit(0)
event("UNHANDLED:" + method + " " + url)
sys.exit(1)
STUB_EOF
  chmod +x "$s/bin/curl"
}

make_scratch_with_parent_ts() { # <name> <parent_time_updated_ms>
  SCRATCH="$(mktemp -d "${REAL_HOME:-$HOME}/.cache/cont-wsilence-${1}.XXXXXX")"
  export SCRATCH
  export PYBIN="$(command -v python3)"
  export HOME="$SCRATCH/home"
  export XDG_STATE_DIR="$SCRATCH/state"
  STATE_DIR="$XDG_STATE_DIR/restart-continuations"
  mkdir -p "$HOME/.local/share/opencode" "$STATE_DIR"
  PARENT_TS="$2" PYBIN="$PYBIN" HOME="$HOME" python3 - <<'DBEOF'
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
  write_stub "$SCRATCH"
  export PATH="$SCRATCH/bin:$PATH"
  mkdir -p "$HOME/d1/.omo/run-continuation/wakes"
  : > "$STATE_DIR/snapshot-$UNIT-20261016-000000.json"   # empty stop snapshot; wake union drives everything
}
cleanup_scratch() { [[ -n "${SCRATCH:-}" ]] && rm -rf "$SCRATCH"; }

write_wake() { # <name> <sessionID> <state> <firstDispatchedAt_ms>
  printf '%s\n' "{\"sessionID\":\"$2\",\"state\":\"$3\",\"title\":\"W\",\"firstDispatchedAt\":$4}" \
    > "$HOME/d1/.omo/run-continuation/wakes/$1"
}

run_resume() { bash "$SCRIPT" hook-resume "$UNIT" "http://127.0.0.1:1" "$AUTH_ENV" > "$SCRATCH/out.txt" 2>&1; }

NOW_MS="$(date +%s)000"

# --- A: parent CONTINUED after dispatch -> wake must NOT be re-kicked --------
echo "--- A: parent progressed after dispatch (leak shape) -> no wake post"
DISPATCH_MS="$(( $(date +%s) - 3600 ))000"   # dispatched 1h ago
make_scratch_with_parent_ts a "$NOW_MS"       # parent active NOW (after dispatch)
write_wake w-leak.json sess-1 dispatched-awaiting-output "$DISPATCH_MS"
run_resume
if ! grep -q '^post:wake:sess-1$' "$STUB_LOG"; then
  ok "progressed parent NOT re-kicked from dispatched-awaiting-output wake"
else
  bad "parent-silence predicate missing: progressed parent WAS re-kicked"
fi
cleanup_scratch

# --- B: parent SILENT since dispatch -> wake IS re-kicked (true positive) ----
echo "--- B: parent silent since dispatch -> wake post fires"
make_scratch_with_parent_ts b "$(( $(date +%s) - 3*3600 ))000"   # parent idle 3h
write_wake w-lost.json sess-1 dispatched-awaiting-output "$DISPATCH_MS"
run_resume
if grep -q '^post:wake:sess-1$' "$STUB_LOG"; then
  ok "silent parent re-kicked (lost wake honored)"
else
  bad "true-positive wake dropped for silent parent (stub: $(tr '\n' '|' < "$STUB_LOG"))"
fi
cleanup_scratch

# --- C: fail-open — broken DB path keeps the wake ----------------------------
echo "--- C: DB failure fails OPEN (wake kept)"
make_scratch_with_parent_ts c "$NOW_MS"
write_wake w-open.json sess-1 dispatched-awaiting-output "$DISPATCH_MS"
# point the T1 lookup at a nonexistent DB via the CONTINUATION_DB_PATH override
CONTINUATION_DB_PATH="$SCRATCH/nope.db" run_resume
if grep -q '^post:wake:sess-1$' "$STUB_LOG"; then
  ok "DB failure fails open: wake kept"
else
  bad "DB failure failed CLOSED (wake dropped) — forbidden direction"
fi
cleanup_scratch

echo "regression: $PASS passed | $FAIL failed"
[[ "$FAIL" -eq 0 ]]
