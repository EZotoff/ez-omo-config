#!/usr/bin/env bash
# Test: scripts/continuation-fp-report.py classification correctness (wave A T5).
#
# Fixture DB with known outcomes:
#   - FP nudge: prior assistant message HAS time.completed  -> false positive
#   - TP nudge: prior assistant message LACKS time.completed -> true positive
#   - /tmp dir nudge: excluded entirely
#   - wake nudge + child nudge: per-kind buckets
# Asserts the --json counts exactly. CONTINUATION_DB_PATH points at the fixture.
set -uo pipefail

PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPORT="$SCRIPT_DIR/scripts/continuation-fp-report.py"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/cont-fpreport.XXXXXX")"
cleanup() { rm -rf "$SCRATCH"; }
trap cleanup EXIT

python3 - "$SCRATCH" <<'DBEOF'
import json, os, sqlite3, sys, time
scratch = sys.argv[1]
db = os.path.join(scratch, "opencode.db")
now = time.time() * 1000
con = sqlite3.connect(db)
con.execute("create table session (id text primary key, directory text, title text, time_archived real, time_updated real)")
con.execute("create table message (id text primary key, session_id text, time_created real, time_updated real, data text)")
con.execute("create table part (id text primary key, message_id text, session_id text, time_created real, time_updated real, data text)")
MAINT = "The OpenCode server was restarted for maintenance and your previous turn was interrupted. Continue exactly where you left off."
WAKE = "A background-task wake notification was lost during a server restart. Re-check your background tasks via background_output(task_id=...) and continue the work."
CHILD = "NOTE: this session is a subagent child. The parent session's background-task registry was lost in the server restart."
def session(sid, directory):
    con.execute("insert into session values (?,?,?,?,?)", (sid, directory, "T", None, now))
def nudge(sid, text, at):
    mid = f"m-n-{sid}"
    con.execute("insert into message values (?,?,?,?,?)", (mid, sid, at, at, json.dumps({"role": "user"})))
    con.execute("insert into part values (?,?,?,?,?,?)", (f"p-{mid}", mid, sid, at, at, json.dumps({"type": "text", "text": text, "synthetic": True})))
def assistant(sid, completed, at):
    mid = f"m-a-{sid}-{at}"
    d = {"role": "assistant"}
    if completed is not None:
        d["time"] = {"completed": at + 1000 if completed else None}
    con.execute("insert into message values (?,?,?,?,?)", (mid, sid, at, at, json.dumps(d)))
# FP maintenance: prior assistant completed
session("s-fp", "/home/x/projA"); assistant("s-fp", True, now - 60000); nudge("s-fp", MAINT, now - 30000)
# TP maintenance: prior assistant NOT completed
session("s-tp", "/home/x/projA"); assistant("s-tp", False, now - 60000); nudge("s-tp", MAINT, now - 30000)
# FP wake
session("s-wk", "/home/y/projB"); assistant("s-wk", True, now - 60000); nudge("s-wk", WAKE, now - 30000)
# FP child
session("s-ch", "/home/y/projB"); assistant("s-ch", True, now - 60000); nudge("s-ch", CHILD, now - 30000)
# Excluded: /tmp dir
session("s-tmp", "/tmp/opencode/junk"); assistant("s-tmp", True, now - 60000); nudge("s-tmp", MAINT, now - 30000)
con.commit()
DBEOF

OUT="$(CONTINUATION_DB_PATH="$SCRATCH/opencode.db" python3 "$REPORT" --days 7 --json)"
if python3 - "$OUT" <<'CHECK_EOF'
import json, sys
d = json.loads(sys.argv[1])
s = d["stats"]
errors = []
if s["maintenance"] != {"nudges": 2, "fp": 1, "tp": 1, "unknown": 0, "precision_pct": 50.0}:
    errors.append(f"maintenance wrong: {s['maintenance']}")
if s["wake"]["fp"] != 1 or s["wake"]["nudges"] != 1:
    errors.append(f"wake wrong: {s['wake']}")
if s["child"]["fp"] != 1:
    errors.append(f"child wrong: {s['child']}")
if s["total"]["nudges"] != 4:
    errors.append(f"total wrong (exclusion failed?): {s['total']}")
if errors:
    print("\n".join(errors)); sys.exit(1)
sys.exit(0)
CHECK_EOF
then
  ok "report classifies FP/TP per kind and excludes /tmp"
else
  bad "report output mismatch: $OUT"
fi

# exit status
if CONTINUATION_DB_PATH="$SCRATCH/opencode.db" python3 "$REPORT" --days 7 > /dev/null; then
  ok "exit 0 on success"
else
  bad "non-zero exit on success"
fi

echo "fp-report: $PASS passed | $FAIL failed"
[[ "$FAIL" -eq 0 ]]
