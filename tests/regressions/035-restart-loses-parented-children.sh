#!/usr/bin/env bash
# Regression: a restart must not lose parented (subagent child) sessions.
#
# Defect (fixed by plan restart-continuation-subagent-coverage T1+T2, commits
# c9472d3/bddb5db/42bae1b/bdd65f1): every capture layer dropped sessions with
# a parentID, and no resume path re-prompted them — a server restart silently
# orphaned in-flight subagents (2026-10-12 incident: 6 killed child sessions,
# zero captured).
#
# Contract: with a busy parented entry in the /session listing, hook-snapshot
# captures it into children[] (shape {id,title,directory,status,time_updated,
# parentID:true,parentSessionID}) WITHOUT altering top-level sessions[], and
# hook-resume POSTs the child a child-specific prompt ("subagent child" note)
# via direct prompt_async.
#
# Fully self-contained: scratch HOME (fake session DB drives discover_dirs),
# scratch XDG_STATE_DIR, stub curl on PATH. No server, no network.
# The paired .kill.sh proves the PRE-fix script (git e9554f8, pre-T1) drops
# the parented entry, and cleans this test's scratch if it dies mid-run.
set -euo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/helpers.sh"

SCRIPT="$(cd "$(dirname "$0")/../.." && pwd)/scripts/restart-with-continuation.sh"

if ! command -v python3 >/dev/null 2>&1; then
  echo "FAIL: python3 required"; exit 1
fi

REAL_HOME="$HOME"
mkdir -p "$REAL_HOME/.cache" /tmp/opencode
SCRATCH="$(mktemp -d "$REAL_HOME/.cache/cont-children.XXXXXX")"
# Scratch must live OUTSIDE /tmp: discover_dirs() excludes /tmp/% directories.
RUNDIR_FILE=/tmp/opencode/035-restart-loses-parented-children.rundir
printf '%s\n' "$SCRATCH" > "$RUNDIR_FILE"
cleanup() { rm -rf "$SCRATCH"; rm -f "$RUNDIR_FILE"; }
trap cleanup EXIT

export HOME="$SCRATCH/home"
export XDG_STATE_DIR="$SCRATCH/state"
STATE_DIR="$XDG_STATE_DIR/restart-continuations"
mkdir -p "$HOME/.local/share/opencode" "$STATE_DIR" "$SCRATCH/bin" "$HOME/d1"
PYBIN="$(command -v python3)"

UNIT="cont-children.service"

# --- fake session DB (one recently-active dir for discover_dirs) --------------
"$PYBIN" - <<'DBEOF'
import os, sqlite3, time
db = os.path.join(os.environ["HOME"], ".local/share/opencode/opencode.db")
con = sqlite3.connect(db)
con.execute("create table session (id text primary key, directory text,"
            " time_updated real, time_archived real, parent_id text, title text)")
con.execute("insert into session values (?,?,?,?,?,?)",
            ("sess-1", os.path.join(os.environ["HOME"], "d1"),
             time.time() * 1000, None, None, "P1"))
con.commit()
DBEOF

# --- stub curl: busy parent + busy PARENTED child in the same directory -------
cat > "$SCRATCH/bin/curl" <<STUB_EOF
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
body = args[args.index("-d") + 1] if "-d" in args else ""
p = urlparse(args[-1])
q = parse_qs(p.query)
D1 = os.path.join(os.environ["HOME"], "d1")
if method == "GET" and p.path == "/session/status" and not q:
    event("probe"); print("{}"); sys.exit(0)
if method == "GET" and p.path == "/session/status":
    event("status:" + unquote(q["directory"][0]))
    print(json.dumps({"sess-1": {"type": "busy"}, "child-1": {"type": "busy"}})); sys.exit(0)
if method == "GET" and p.path == "/session":
    event("sessions:" + unquote(q.get("directory", [""])[0]))
    print(json.dumps([
        {"id": "sess-1", "title": "P1", "directory": D1, "parentID": None,
         "time": {"updated": 1000}},
        {"id": "child-1", "title": "C1", "directory": D1, "parentID": "sess-1",
         "time": {"updated": 1000}}])); sys.exit(0)
if method == "POST" and p.path.endswith("/prompt_async"):
    sid = p.path.split("/")[-2]
    event("post:" + sid)
    if "subagent child" in body:
        event("childbody:" + sid)
    print("ok"); sys.exit(0)
event("UNHANDLED:" + method + " " + args[-1]); sys.exit(1)
STUB_EOF
chmod +x "$SCRATCH/bin/curl"
export SCRATCH
export PATH="$SCRATCH/bin:$PATH"
: > "$SCRATCH/stub.log"

AUTH_ENV="$SCRATCH/auth.env"
printf 'OPENCODE_SERVER_PASSWORD=testpass\n' > "$AUTH_ENV"
URL="http://127.0.0.1:1"
export CONTINUATION_JOURNAL_TAG=restart-continuation-test

fail=0

# --- (a) capture: parented entry lands in children[], NOT in sessions[] -------
bash "$SCRIPT" hook-snapshot "$UNIT" "$URL" "$AUTH_ENV" > "$SCRATCH/snap.out" 2>&1
SNAP="$(ls -t "$STATE_DIR"/snapshot-$UNIT-*.json 2>/dev/null | head -1 || true)"
if [[ -n "$SNAP" && -s "$SNAP" ]]; then
  "$PYBIN" - "$SNAP" > "$SCRATCH/shape.json" <<'PYEOF'
import json, sys
snap = json.load(open(sys.argv[1]))
ids = [s["id"] for s in snap.get("sessions", [])]
kids = snap.get("children", [])
c = kids[0] if kids else {}
print(json.dumps({
    "top_ids": sorted(ids),
    "n_children": len(kids),
    "child": {"id": c.get("id"), "has_title": "title" in c,
              "has_directory": "directory" in c, "has_status": "status" in c,
              "has_time_updated": "time_updated" in c,
              "parentID": c.get("parentID"),
              "parentSessionID": c.get("parentSessionID")},
}))
PYEOF
  if [[ "$(jq -r '.n_children' "$SCRATCH/shape.json")" == "1" \
     && "$(jq -r '.child.id' "$SCRATCH/shape.json")" == "child-1" \
     && "$(jq -r '.child.parentID' "$SCRATCH/shape.json")" == "true" \
     && "$(jq -r '.child.parentSessionID' "$SCRATCH/shape.json")" == "sess-1" \
     && "$(jq -r '.child.has_title' "$SCRATCH/shape.json")" == "true" \
     && "$(jq -r '.child.has_directory' "$SCRATCH/shape.json")" == "true" \
     && "$(jq -r '.child.has_status' "$SCRATCH/shape.json")" == "true" \
     && "$(jq -r '.child.has_time_updated' "$SCRATCH/shape.json")" == "true" \
     && "$(jq -r '.top_ids | index("child-1")' "$SCRATCH/shape.json")" == "null" \
     && "$(jq -r '.top_ids | index("sess-1")' "$SCRATCH/shape.json")" != "null" ]]; then
    echo "PASS (a): capture keeps sessions[] semantics; child captured in children[] with full shape"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo "FAIL (a): wrong capture shape: $(cat "$SCRATCH/shape.json")"
    TESTS_FAILED=$((TESTS_FAILED + 1)); fail=1
  fi
else
  echo "FAIL (a): no snapshot written ($(cat "$SCRATCH/snap.out" | tail -3))"
  TESTS_FAILED=$((TESTS_FAILED + 1)); fail=1
fi

# --- (b) resume: child POSTed directly with the child prompt ------------------
bash "$SCRIPT" hook-resume "$UNIT" "$URL" "$AUTH_ENV" > "$SCRATCH/resume.out" 2>&1
if grep -q '^post:child-1$' "$SCRATCH/stub.log" && grep -q '^childbody:child-1$' "$SCRATCH/stub.log" \
   && grep -q '^post:sess-1$' "$SCRATCH/stub.log"; then
  echo "PASS (b): hook-resume POSTed parent (plain prompt) AND child (child prompt) via prompt_async"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo "FAIL (b): stub.log missing child/parent resume POSTs (stub.log: $(tr '\n' '|' < "$SCRATCH/stub.log"))"
  sed 's/^/    /' "$SCRATCH/resume.out" >&2 || true
  TESTS_FAILED=$((TESTS_FAILED + 1)); fail=1
fi

echo "=========================================="
echo "035-restart-loses-parented-children: $TESTS_PASSED passed | $TESTS_FAILED failed"
echo "=========================================="
[[ $fail -eq 0 ]]
