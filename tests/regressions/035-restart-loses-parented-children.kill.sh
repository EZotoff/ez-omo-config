#!/usr/bin/env bash
# Kill-test 035: proves the pre-fix script DROPPED parented (subagent child)
# sessions — the bug 035-restart-loses-parented-children.sh guards against.
#
# Runs the PRE-T1 script (git e9554f8, before commit c9472d3 introduced
# children[] capture) against the same busy-parent + busy-parented-child stub:
# its snapshot must contain NO children array and must NOT list the child
# top-level — i.e. the restart silently lost the child. If the pre-fix source
# revision is unavailable (shallow clone / rewritten history), SKIP like
# kill-test 017. Also cleans this pair's scratch dir if the main test died.
set -euo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/helpers.sh"

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
PRE_FIX_REF="e9554f8"
RUNDIR_FILE=/tmp/opencode/035-restart-loses-parented-children.rundir

# --- cleanup duty (034-style): reclaim any scratch the main test left ----------
if [[ -f "$RUNDIR_FILE" ]]; then
  rundir="$(cat "$RUNDIR_FILE")"
  case "$rundir" in
    */.cache/cont-children.*) rm -rf "$rundir" ;;
    *) echo "SKIP: refusing to remove unexpected path: $rundir" ;;
  esac
  rm -f "$RUNDIR_FILE"
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "SKIP: python3 required"; exit 0
fi
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq required"; exit 0; }
OLD_SRC="$(git -C "$REPO" show "$PRE_FIX_REF:scripts/restart-with-continuation.sh" 2>/dev/null || true)"
if [[ -z "$OLD_SRC" ]]; then
  echo "SKIP: pre-fix revision $PRE_FIX_REF not available in git history"
  exit 0
fi

REAL_HOME="$HOME"
SCRATCH="$(mktemp -d "${REAL_HOME:-$HOME}/.cache/cont-children-kill.XXXXXX")"
cleanup() { rm -rf "$SCRATCH"; }
trap cleanup EXIT

export HOME="$SCRATCH/home"
export XDG_STATE_DIR="$SCRATCH/state"
STATE_DIR="$XDG_STATE_DIR/restart-continuations"
mkdir -p "$HOME/.local/share/opencode" "$STATE_DIR" "$SCRATCH/bin" "$HOME/d1"
PYBIN="$(command -v python3)"
OLD="$SCRATCH/restart-with-continuation.prefix.sh"
printf '%s\n' "$OLD_SRC" > "$OLD"

UNIT="cont-children.service"

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
    event("post:" + p.path.split("/")[-2]); print("ok"); sys.exit(0)
event("UNHANDLED:" + method + " " + args[-1]); sys.exit(1)
STUB_EOF
chmod +x "$SCRATCH/bin/curl"
export SCRATCH
export PATH="$SCRATCH/bin:$PATH"
: > "$SCRATCH/stub.log"

AUTH_ENV="$SCRATCH/auth.env"
printf 'OPENCODE_SERVER_PASSWORD=testpass\n' > "$AUTH_ENV"
export CONTINUATION_JOURNAL_TAG=restart-continuation-test

# Pre-fix capture: the parented child must VANISH (no children[], not top-level).
bash "$OLD" hook-snapshot "$UNIT" "http://127.0.0.1:1" "$AUTH_ENV" \
  > "$SCRATCH/snap.out" 2>&1 || true
SNAP="$(ls -t "$STATE_DIR"/snapshot-$UNIT-*.json 2>/dev/null | head -1 || true)"
[[ -n "$SNAP" && -s "$SNAP" ]] || { echo "FAIL: pre-fix script wrote no snapshot"; exit 1; }

"$PYBIN" - "$SNAP" > "$SCRATCH/old-shape.json" <<'PYEOF'
import json, sys
snap = json.load(open(sys.argv[1]))
print(json.dumps({
    "has_children_key": "children" in snap,
    "top_ids": sorted(s["id"] for s in snap.get("sessions", [])),
}))
PYEOF

has_children="$(jq -r '.has_children_key' "$SCRATCH/old-shape.json")"
child_top="$(jq -r '.top_ids | index("child-1")' "$SCRATCH/old-shape.json")"
parent_top="$(jq -r '.top_ids | index("sess-1")' "$SCRATCH/old-shape.json")"

# Pre-fix resume: nothing to re-prompt for the child — it was never captured.
bash "$OLD" hook-resume "$UNIT" "http://127.0.0.1:1" "$AUTH_ENV" \
  > "$SCRATCH/resume.out" 2>&1 || true
if [[ "$has_children" == "false" && "$child_top" == "null" && "$parent_top" != "null" ]] \
   && ! grep -q '^post:child-1$' "$SCRATCH/stub.log"; then
  echo "PASS: pre-fix script dropped the parented child (no children[], absent top-level, never re-prompted) — bug proven"
  exit 0
fi
echo "FAIL: pre-fix revision $PRE_FIX_REF did NOT drop the parented child (shape: $(cat "$SCRATCH/old-shape.json"); posts: $(tr '\n' '|' < "$SCRATCH/stub.log")) — kill-test broken"
exit 1
