#!/usr/bin/env bash
# test_continuation_hooks.sh — TDD tests for restart-with-continuation.sh
# continuation-net hardening (plan .omo/plans/continuation-net-hardening-20261001.md):
#   1. snapshot budget overrun still WRITES partial inventory (partial: true)
#   2. hook-resume retries readiness probes AND prompt POSTs on rc=7
#   3. bypass flags still skip snapshot+resume (regression)
#   4. normal full inventory unchanged (regression)
#
# Isolation: scratch HOME (fake session DB drives discover_dirs), scratch
# XDG_STATE_DIR (STATE_DIR), stub curl on PATH (python3). Only `curl` is stubbed.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/../scripts/restart-with-continuation.sh"
UNIT="test-unit.service"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# ---------------------------------------------------------------- stub curl --
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
def count(pat):
    try:
        return sum(1 for l in open(LOG) if l.startswith(pat))
    except OSError:
        return 0
args = sys.argv[1:]
method = "GET"
if "-X" in args:
    method = args[args.index("-X") + 1]
url = args[-1]
p = urlparse(url)
q = parse_qs(p.query)
if method == "GET" and p.path == "/session/status" and not q:
    event("probe")
    if count("probe") <= int(os.environ.get("STUB_REFUSE_PROBES", "0")):
        sys.exit(7)
    print("{}")
    sys.exit(0)
if method == "GET" and p.path == "/session/status" and "directory" in q:
    d = unquote(q["directory"][0])
    event("status:" + d)
    time.sleep(float(os.environ.get("STUB_STATUS_SLEEP", "0")))
    idx = os.path.basename(d).lstrip("d")
    print(json.dumps({"sess-" + idx: {"type": "busy"}}))
    sys.exit(0)
if method == "GET" and p.path == "/session":
    d = unquote(q.get("directory", [""])[0])
    event("sessions:" + d)
    idx = os.path.basename(d).lstrip("d")
    print(json.dumps([{"id": "sess-" + idx, "title": "T" + idx,
                       "directory": d, "parentID": None,
                       "time": {"updated": 1000}}]))
    sys.exit(0)
if method == "POST" and p.path.endswith("/prompt_async"):
    sid = p.path.split("/")[-2]
    event("post:" + sid)
    if count("post:") <= int(os.environ.get("STUB_REFUSE_POSTS", "0")):
        sys.exit(7)
    print("ok")
    sys.exit(0)
event("UNHANDLED:" + method + " " + url)
sys.exit(1)
STUB_EOF
  chmod +x "$s/bin/curl"
}

# ------------------------------------------------------------- scratch setup --
make_scratch() { # make_scratch <name>  -> sets SCRATCH STATE_DIR AUTH_ENV env
  SCRATCH="$(mktemp -d "/tmp/opencode/cont-hooks-${1}.XXXXXX")"
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
for i in (1, 2, 3):
    con.execute("insert into session values (?,?,?,?,?,?)",
                (f"sess-{i}", os.path.join(os.environ["HOME"], f"d{i}"),
                 time.time() * 1000, None, None, f"T{i}"))  # ms, like the real DB
con.commit()
DBEOF
  AUTH_ENV="$SCRATCH/auth.env"
  printf 'OPENCODE_SERVER_PASSWORD=testpass\n' > "$AUTH_ENV"
  export STUB_LOG="$SCRATCH/stub.log"
  export STUB_REFUSE_PROBES=0 STUB_REFUSE_POSTS=0 STUB_STATUS_SLEEP=0  # reset per test
  : > "$STUB_LOG"
  write_stub "$SCRATCH"
  export PATH="$SCRATCH/bin:$PATH"
}
cleanup_scratch() { [[ -n "${SCRATCH:-}" ]] && rm -rf "$SCRATCH"; }

newest_snapshot() { ls -t "$STATE_DIR"/snapshot-$UNIT-*.json 2>/dev/null | head -1; }
snap_sessions() { # snap_sessions <file> -> count of sessions[]
  PYBIN="$PYBIN" python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1])).get("sessions",[])))' "$1" 2>/dev/null
}
snap_partial() { # snap_partial <file> -> value of partial key ('' if absent)
  PYBIN="$PYBIN" python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("partial",""))' "$1" 2>/dev/null
}

# ===================================================================== test 1
test_partial_write_on_budget_overrun() {
  echo "--- test 1: budget overrun writes partial snapshot (RED: no file)"
  make_scratch t1
  trap cleanup_scratch RETURN
  export STUB_STATUS_SLEEP=3
  local out rc=0
  SNAPSHOT_BUDGET_SECONDS=2 \
    bash "$SCRIPT" hook-snapshot "$UNIT" "http://127.0.0.1:1" "$AUTH_ENV" > "$SCRATCH/out.txt" 2>&1 || rc=$?
  local f; f="$(newest_snapshot)"
  if [[ -n "$f" && -s "$f" ]]; then
    local n p
    n="$(snap_sessions "$f")"; p="$(snap_partial "$f")"
    if [[ "$n" == "3" && "$p" == "True" ]]; then
      ok "partial snapshot written: $n sessions, partial=$p"
    else
      bad "partial snapshot wrong shape: sessions=$n partial=$p (file $f)"
    fi
  else
    bad "no snapshot file written on budget overrun (rc=$rc) — partial inventory DISCARDED"
  fi
}

# ===================================================================== test 2
test_resume_retries() {
  echo "--- test 2: hook-resume retries rc=7 probes AND prompt POSTs"
  make_scratch t2
  trap cleanup_scratch RETURN
  printf '%s\n' '{"sessions":[{"id":"sess-1","title":"T1","directory":"'"$HOME"'/d1","status":"busy"}]}' \
    > "$STATE_DIR/snapshot-$UNIT-20261001-000000.json"
  export STUB_REFUSE_PROBES=2   # readiness probe: refuse x2, succeed on 3rd
  export STUB_REFUSE_POSTS=1    # prompt POST: refuse once, succeed on retry
  local out rc=0
  bash "$SCRIPT" hook-resume "$UNIT" "http://127.0.0.1:1" "$AUTH_ENV" > "$SCRATCH/out.txt" 2>&1 || rc=$?
  local probes posts
  probes="$(grep -c '^probe$' "$STUB_LOG" || true)"
  posts="$(grep -c '^post:sess-1$' "$STUB_LOG" || true)"
  if [[ "$probes" -ge 3 ]]; then
    ok "readiness probe retried ($probes attempts)"
  else
    bad "readiness probe single-shot (attempts=$probes)"
  fi
  if [[ "$posts" -ge 2 ]]; then
    ok "prompt POST retried to success ($posts attempts)"
  else
    bad "prompt POST gave up after first rc=7 (attempts=$posts)"
  fi
  if grep -q 'resumed=1 failed=0' "$STATE_DIR/hooks.log"; then
    ok "resume succeeded (resumed=1 in hooks.log)"
  else
    bad "resume did not report resumed=1 (rc=$rc); hooks.log: $(tail -3 "$STATE_DIR/hooks.log" 2>/dev/null | tr '\n' '|')"
  fi
}

# ===================================================================== test 3
test_bypass_regression() {
  echo "--- test 3: bypass flag skips snapshot AND resume"
  make_scratch t3
  trap cleanup_scratch RETURN
  touch "$STATE_DIR/.bypass-$UNIT"
  bash "$SCRIPT" hook-snapshot "$UNIT" "http://127.0.0.1:1" "$AUTH_ENV" > "$SCRATCH/out.txt" 2>&1
  if [[ -z "$(newest_snapshot)" && ! -s "$STUB_LOG" ]]; then
    ok "snapshot skipped under bypass (no probes, no file)"
  else
    bad "snapshot NOT skipped under bypass (stub.log: $(cat "$STUB_LOG" | tr '\n' '|'))"
  fi
  printf '%s\n' '{"sessions":[{"id":"sess-1","title":"T1","directory":"x","status":"busy"}]}' \
    > "$STATE_DIR/snapshot-$UNIT-20261001-000000.json"
  bash "$SCRIPT" hook-resume "$UNIT" "http://127.0.0.1:1" "$AUTH_ENV" > "$SCRATCH/out.txt" 2>&1
  if ! grep -q '^post:' "$STUB_LOG"; then
    ok "resume skipped under bypass (no POST)"
  else
    bad "resume NOT skipped under bypass"
  fi
}

# ===================================================================== test 4
test_full_inventory_regression() {
  echo "--- test 4: normal full inventory unchanged"
  make_scratch t4
  trap cleanup_scratch RETURN
  export STUB_STATUS_SLEEP=0
  bash "$SCRIPT" hook-snapshot "$UNIT" "http://127.0.0.1:1" "$AUTH_ENV" > "$SCRATCH/out.txt" 2>&1
  local f; f="$(newest_snapshot)"
  if [[ -n "$f" && -s "$f" ]]; then
    local n p
    n="$(snap_sessions "$f")"; p="$(snap_partial "$f")"
    if [[ "$n" == "3" && -z "$p" ]]; then
      ok "full inventory: $n sessions, no partial marker"
    else
      bad "full inventory wrong: sessions=$n partial='$p'"
    fi
  else
    bad "no snapshot written for healthy server"
  fi
}

# ================================================================= test 5
test_resume_dedup() {
  echo "--- test 5: second resume pass over the same session skips (no re-inject)"
  make_scratch t5
  trap cleanup_scratch RETURN
  printf '%s\n' '{"sessions":[{"id":"sess-1","title":"T1","directory":"'"$HOME"'/d1","status":"busy"}]}' \
    > "$STATE_DIR/snapshot-$UNIT-20261001-000000.json"
  local rc1=0 rc2=0
  # Incident shape (2026-10-02 16:58): the SAME session appears in TWO
  # different snapshot generations — the one-shot consumption of gen A must
  # not open the door for gen B to re-inject the same resume prompt.
  bash "$SCRIPT" hook-resume "$UNIT" "http://127.0.0.1:1" "$AUTH_ENV" > "$SCRATCH/out1.txt" 2>&1 || rc1=$?
  printf '%s\n' '{"sessions":[{"id":"sess-1","title":"T1","directory":"'"$HOME"'/d1","status":"busy"}]}' \
    > "$STATE_DIR/snapshot-$UNIT-20261001-000100.json"
  bash "$SCRIPT" hook-resume "$UNIT" "http://127.0.0.1:1" "$AUTH_ENV" > "$SCRATCH/out2.txt" 2>&1 || rc2=$?
  local posts dupskips
  posts="$(grep -c '^post:sess-1$' "$STUB_LOG" || true)"
  local hlog; hlog="$(find "$SCRATCH" -name 'hooks.log' | head -1)"
  dupskips="$(grep -c 'skip-dup' "$hlog" || true)"
  if [[ $rc1 -eq 0 && $posts -ge 1 && $dupskips -ge 1 ]]; then
    echo "PASS: first pass resumed, second pass skipped via dedup"
    PASS=$((PASS+1))
  else
    echo "FAIL: rc1=$rc1 rc2=$rc2 posts=$posts dupskips=$dupskips"
    echo "--- out1.txt ---"; cat "$SCRATCH/out1.txt" 2>/dev/null | tail -15
    echo "--- out2.txt ---"; cat "$SCRATCH/out2.txt" 2>/dev/null | tail -8
    echo "--- hooks.log ---"; find "$SCRATCH" -name 'hooks.log' -exec tail -15 {} \; 2>/dev/null
    echo "--- stub.log ---"; cat "$STUB_LOG" 2>/dev/null | tail -5
    FAIL=$((FAIL+1))
  fi
}

test_partial_write_on_budget_overrun
test_resume_retries
test_resume_dedup
test_bypass_regression
test_full_inventory_regression

echo "=========================================="
echo "continuation-hooks: $PASS passed | $FAIL failed"
echo "=========================================="
[[ $FAIL -eq 0 ]]
