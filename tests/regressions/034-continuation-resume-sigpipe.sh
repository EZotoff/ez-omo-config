#!/usr/bin/env bash
# Regression: a script-driven restart must survive a large snapshot state dir.
#
# Defect (fixed 2026-10-11): line 993 built the resume target with
#   resume "$(ls -t "$STATE_DIR"/snapshot-*.json 2>/dev/null | head -1 || echo "$STATE_FILE")"
# under `set -euo pipefail`. Once the state dir holds enough snapshot files that
# `ls` output exceeds the pipe buffer, `head -1` closes the pipe early, `ls` dies
# of SIGPIPE (exit 141), pipefail propagates the non-zero status, and the
# `|| echo "$STATE_FILE"` fallback fires INSIDE the same command substitution —
# appending a second line. resume() then open()s "X\nX" and python aborts with
# FileNotFoundError; `set -e` kills the whole invocation (rc=1) and NO session is
# resumed. Hooks are bypassed on this path by design, so line 993 is the only
# resume mechanism for a script-driven restart, and each run added 1-2 more
# snapshot files — self-aggravating.
#
# Case: seed ~1000 snapshot files (path bytes > 64 KiB pipe buffer) in a scratch
# state dir, stub curl + systemctl, run --restart, and require: rc=0, a
# prompt_async POST delivered, the newest snapshot consumed, and the fatal idiom
# absent from the script (race-free static assertion).
#
# Fully self-contained: scratch HOME (fake session DB drives discover_dirs),
# scratch XDG_STATE_DIR, stub curl/systemctl on PATH. No server, no network.
set -uo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/helpers.sh"

SCRIPT="$(cd "$(dirname "$0")/../.." && pwd)/scripts/restart-with-continuation.sh"

if ! command -v python3 >/dev/null 2>&1; then
  echo "FAIL: python3 required"
  exit 1
fi

REAL_HOME="$HOME"
mkdir -p "$REAL_HOME/.cache" /tmp/opencode
SCRATCH="$(mktemp -d "$REAL_HOME/.cache/cont-sigpipe.XXXXXX")"
# Scratch must live OUTSIDE /tmp: discover_dirs() excludes /tmp/% directories.
RUNDIR_FILE=/tmp/opencode/034-continuation-resume-sigpipe.rundir
PIDFILE=/tmp/opencode/034-continuation-resume-sigpipe.pids
printf '%s\n' "$SCRATCH" > "$RUNDIR_FILE"
: > "$PIDFILE"

cleanup() {
  rm -rf "$SCRATCH"
  rm -f "$RUNDIR_FILE" "$PIDFILE"
}
trap cleanup EXIT

export HOME="$SCRATCH/home"
export XDG_STATE_DIR="$SCRATCH/state"
STATE_DIR="$XDG_STATE_DIR/restart-continuations"
mkdir -p "$HOME/.local/share/opencode" "$STATE_DIR" "$SCRATCH/bin"

PYBIN="$(command -v python3)"
export PYBIN

# --- fake session DB (3 recently-active dirs for discover_dirs) --------------
"$PYBIN" - <<'DBEOF'
import os, sqlite3, time
db = os.path.join(os.environ["HOME"], ".local/share/opencode/opencode.db")
con = sqlite3.connect(db)
con.execute("create table session (id text primary key, directory text,"
            " time_updated real, time_archived real, parent_id text, title text)")
for i in (1, 2, 3):
    con.execute("insert into session values (?,?,?,?,?,?)",
                (f"sess-{i}", os.path.join(os.environ["HOME"], f"d{i}"),
                 time.time() * 1000, None, None, f"T{i}"))
con.commit()
DBEOF

# --- stub curl: GET /session/status, GET /session, POST prompt_async ---------
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
p = urlparse(args[-1])
q = parse_qs(p.query)
if method == "GET" and p.path == "/session/status" and not q:
    event("probe"); print("{}"); sys.exit(0)
if method == "GET" and p.path == "/session/status":
    d = unquote(q["directory"][0]); event("status:" + d)
    idx = os.path.basename(d).lstrip("d")
    print(json.dumps({"sess-" + idx: {"type": "busy"}})); sys.exit(0)
if method == "GET" and p.path == "/session":
    d = unquote(q.get("directory", [""])[0]); event("sessions:" + d)
    idx = os.path.basename(d).lstrip("d")
    print(json.dumps([{"id": "sess-" + idx, "title": "T" + idx,
                       "directory": d, "parentID": None,
                       "time": {"updated": 1000}}])); sys.exit(0)
if method == "POST" and p.path.endswith("/prompt_async"):
    sid = p.path.split("/")[-2]; event("post:" + sid); print("ok"); sys.exit(0)
event("UNHANDLED:" + method + " " + args[-1]); sys.exit(1)
STUB_EOF
chmod +x "$SCRATCH/bin/curl"

# --- stub systemctl (the restart call only) ----------------------------------
cat > "$SCRATCH/bin/systemctl" <<'SCTL'
#!/usr/bin/env bash
printf 'systemctl %s\n' "$*" >> "${SCRATCH}/stub.log"
exit 0
SCTL
chmod +x "$SCRATCH/bin/systemctl"

export SCRATCH
export PATH="$SCRATCH/bin:$PATH"
: > "$SCRATCH/stub.log"

AUTH_ENV="$SCRATCH/auth.env"
printf 'OPENCODE_SERVER_PASSWORD=testpass\n' > "$AUTH_ENV"

# --- seed 1000 snapshots: state-dir path bytes > 64 KiB pipe buffer ----------
for i in $(seq 1 1000); do
  : > "$STATE_DIR/snapshot-20260101-$(printf '%06d' "$i").json"
done

# --- run the script-driven restart -------------------------------------------
RC=0
CONTINUATION_JOURNAL_TAG=restart-continuation-test \
  bash "$SCRIPT" --restart --url http://127.0.0.1:1 --auth-env "$AUTH_ENV" \
  > "$SCRATCH/out.txt" 2>&1 || RC=$?

fail=0

# (a) the invocation must not abort
if [[ "$RC" -eq 0 ]]; then
  echo "PASS (a): script-driven restart exited rc=0"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo "FAIL (a): script-driven restart aborted rc=$RC — newest-snapshot selection produced a multi-line SESSIONS_FILE (SIGPIPE fallback appended \$STATE_FILE)"
  grep -m1 -A3 'FileNotFoundError' "$SCRATCH/out.txt" | sed 's/^/    /' || true
  TESTS_FAILED=$((TESTS_FAILED + 1)); fail=1
fi

# (b) at least one resume POST must be delivered
if grep -q '^post:sess-' "$SCRATCH/stub.log"; then
  echo "PASS (b): resume prompt POST delivered ($(grep -c '^post:sess-' "$SCRATCH/stub.log") session(s))"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo "FAIL (b): no prompt_async POST delivered — resume aborted before dispatch"
  TESTS_FAILED=$((TESTS_FAILED + 1)); fail=1
fi

# (c) the resumed snapshot must be consumed (state dir must not grow forever)
if ls "$STATE_DIR"/consumed-snapshot-* >/dev/null 2>&1; then
  echo "PASS (c): resumed snapshot consumed ($(basename "$(ls -t "$STATE_DIR"/consumed-snapshot-* | head -1)"))"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo "FAIL (c): resumed snapshot not consumed in script path (no consumed-* rename; state dir grows unboundedly)"
  TESTS_FAILED=$((TESTS_FAILED + 1)); fail=1
fi

# (d) race-free static check: the fatal idiom must be gone
idiom_count="$(grep -c 'head -1 || echo "$STATE_FILE"' "$SCRIPT" || true)"
if [[ "${idiom_count:-0}" -eq 0 ]]; then
  echo "PASS (d): resume site free of the pipefail-fatal ls|head||echo idiom"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo "FAIL (d): resume site still uses the pipefail-fatal ls|head||echo idiom (line 993)"
  TESTS_FAILED=$((TESTS_FAILED + 1)); fail=1
fi

if ! bash -n "$SCRIPT"; then
  echo "FAIL: script syntax error"
  TESTS_FAILED=$((TESTS_FAILED + 1)); fail=1
fi

echo "=========================================="
echo "034-continuation-resume-sigpipe: $TESTS_PASSED passed | $TESTS_FAILED failed"
echo "=========================================="
[[ $fail -eq 0 ]]
