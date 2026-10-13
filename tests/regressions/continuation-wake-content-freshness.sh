#!/usr/bin/env bash
# Regression: union_wakes judges wake freshness by CONTENT age, never mtime.
#
# Contract (plan: continuation-idle-kickstart-fix T1; 2026-10-13 incident): an
# unidentified writer mass-refreshed 19 stale wake files' mtimes in 4ms, so the
# old mtime gate (age = now - getmtime) unioned months-old leftovers into every
# restart and re-prompted idle sessions. Freshness must come from the timestamps
# recorded INSIDE the wake (firstDispatchedAt/dispatchedAt/claimedAt/history[-1].at,
# ms-epoch, 6h cap); a wake with no readable content timestamp is skipped.
#
# Harness: scratch HOME (fake opencode.db drives discover_dirs), stub curl on
# PATH, real script invoked via `hook-resume`. SCRIPT env override lets the
# paired .kill.sh point the SAME scenarios at a deliberately-bugged copy.
set -uo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/helpers.sh"

SCRIPT="${SCRIPT:-$(cd "$(dirname "$0")/../.." && pwd)/scripts/restart-with-continuation.sh}"
REAL_HOME="$HOME"
UNIT="reg-wake.service"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

write_stub() { # write_stub <scratch>
  local s="$1"
  mkdir -p "$s/bin"
  cat > "$s/bin/curl" <<STUB_EOF
#!$PYBIN
import json, os, sys, time
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
    event("probe")
    print("{}")
    sys.exit(0)
if method == "GET" and p.path == "/session/status" and "directory" in q:
    event("status:" + unquote(q["directory"][0]))
    print("{}")
    sys.exit(0)
if method == "GET" and p.path == "/session":
    d = unquote(q.get("directory", [""])[0])
    event("sessions:" + d)
    print(json.dumps([{"id": "sess-1", "title": "T1", "directory": d,
                       "parentID": None, "time": {"updated": 1000}}]))
    sys.exit(0)
if method == "POST" and p.path.endswith("/prompt_async"):
    sid = p.path.split("/")[-2]
    event("post:" + sid)
    body = args[args.index("-d") + 1] if "-d" in args else ""
    if "wake notification was lost" in body:
        event("wakebody:" + sid)
    print("ok")
    sys.exit(0)
event("UNHANDLED:" + method + " " + url)
sys.exit(1)
STUB_EOF
  chmod +x "$s/bin/curl"
}

make_scratch() { # make_scratch <name>
  SCRATCH="$(mktemp -d "${REAL_HOME:-$HOME}/.cache/cont-wake-${1}.XXXXXX")"
  export SCRATCH
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
  export STUB_LOG="$SCRATCH/stub.log"
  : > "$STUB_LOG"
  write_stub "$SCRATCH"
  export PATH="$SCRATCH/bin:$PATH"
  mkdir -p "$HOME/d1/.omo/run-continuation/wakes"
  printf '%s\n' '{"sessions":[{"id":"sess-1","title":"T1","directory":"'"$HOME"'/d1","status":"busy"}]}' \
    > "$STATE_DIR/snapshot-$UNIT-20261013-000000.json"
}
cleanup_scratch() { [[ -n "${SCRATCH:-}" ]] && rm -rf "$SCRATCH"; }

# write_wake <name> <sessionID> <state> <firstDispatchedAt_ms|-> [mtime_touch]
write_wake() {
  local name="$1" sid="$2" state="$3" ts="$4" touch="$5"
  local wf="$HOME/d1/.omo/run-continuation/wakes/$name"
  if [[ "$ts" == "-" ]]; then
    printf '%s\n' "{\"sessionID\":\"$sid\",\"state\":\"$state\",\"title\":\"W\"}" > "$wf"
  else
    printf '%s\n' "{\"sessionID\":\"$sid\",\"state\":\"$state\",\"title\":\"W\",\"firstDispatchedAt\":$ts}" > "$wf"
  fi
  [[ "$touch" == "touch" ]] && touch "$wf"
}

run_resume() { bash "$SCRIPT" hook-resume "$UNIT" "http://127.0.0.1:1" "$AUTH_ENV" > "$SCRATCH/out.txt" 2>&1; }

# --- A: stale content + fresh mtime must NOT be unioned ----------------------
echo "--- A: mtime-freshened stale wake is skipped"
make_scratch a
STALE_MS="$(( ($(date +%s) - 7*3600) * 1000 ))"
write_wake w-stale.json wake-stale dispatched-awaiting-output "$STALE_MS" touch
run_resume
if ! grep -q '^post:wake-stale$' "$STUB_LOG"; then
  ok "stale-content/fresh-mtime wake NOT unioned (no post:wake-stale)"
else
  bad "stale wake was unioned despite 7h-old content (mtime gate still active?)"
fi

cleanup_scratch

# --- B: fresh content wake IS unioned with WAKE_PROMPT ------------------------
echo "--- B: fresh-content wake is unioned with WAKE_PROMPT"
make_scratch b
FRESH_MS="$(( ($(date +%s) - 3600) * 1000 ))"
write_wake w-fresh.json wake-fresh dispatched-awaiting-output "$FRESH_MS" ""
run_resume
if grep -q '^post:wake-fresh$' "$STUB_LOG" && grep -q '^wakebody:wake-fresh$' "$STUB_LOG"; then
  ok "fresh wake unioned with WAKE_PROMPT body"
else
  bad "fresh wake not unioned (stub: $(tr '\n' '|' < "$STUB_LOG"))"
fi

cleanup_scratch

# --- C: coalesce — two qualifying wakes, same sessionID -> exactly one POST --
echo "--- C: multiple qualifying wakes for one session coalesce to one POST"
make_scratch c
write_wake w-c1.json wake-coalesce dispatched-awaiting-output "$(( ($(date +%s) - 3600) * 1000 ))" ""
write_wake w-c2.json wake-coalesce dispatched-awaiting-output "$(( ($(date +%s) - 300) * 1000 ))" ""
run_resume
n="$(grep -c '^post:wake-coalesce$' "$STUB_LOG" || true)"
if [[ "$n" == "1" ]]; then
  ok "coalesced to exactly one POST for the session"
else
  bad "expected 1 POST for coalesced session, got $n"
fi

cleanup_scratch

# --- D: defensive — malformed + timestamp-less skipped, fresh still delivered -
echo "--- D: malformed JSON and timestamp-less wake skipped without crash"
make_scratch d
printf 'not json at all {{{' > "$HOME/d1/.omo/run-continuation/wakes/garbage.json"
write_wake w-nots.json wake-nots dispatched-awaiting-output "-" ""
write_wake w-fresh2.json wake-fresh2 dispatched-awaiting-output "$(( ($(date +%s) - 600) * 1000 ))" ""
rc=0; run_resume || rc=$?
if [[ $rc -eq 0 ]] && grep -q '^post:wake-fresh2$' "$STUB_LOG" \
   && ! grep -q '^post:wake-nots$' "$STUB_LOG" && ! grep -q 'garbage' "$STUB_LOG"; then
  ok "malformed + timestamp-less skipped; fresh wake still delivered (rc=0)"
else
  bad "defensive handling failed (rc=$rc; stub: $(tr '\n' '|' < "$STUB_LOG"))"
fi

cleanup_scratch

echo "=========================================="
echo "continuation-wake-content-freshness: $PASS passed | $FAIL failed"
cleanup_scratch

echo "=========================================="
[[ $FAIL -eq 0 ]]
