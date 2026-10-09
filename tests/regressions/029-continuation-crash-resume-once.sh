#!/usr/bin/env bash
# Regression: crash-class hook-resume from a checkpoint injects EXACTLY ONCE.
#
# Contract (plan: crashsafe-continuation-hardening Task 8; 2026-09-21 01:00
# incident): with no stop-snapshot but a fresh periodic checkpoint present,
# hook-resume injects one continuation prompt per listed session, touches the
# one-shot .consumed-<unit>-<uuid> marker, and a SECOND invocation injects
# nothing. Guards against the incident's end state (6 sessions orphaned) AND
# against double-prompting if hook-resume fires twice.
#
# Fully self-contained: scratch `opencode serve` on a free ephemeral port
# under /tmp/opencode, one real session created via POST /session, hand-seeded
# checkpoint in a test-local XDG_STATE_DIR, no live-server probes. The paired
# .kill.sh cleans the scratch server if this script is killed mid-run.
set -euo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/helpers.sh"

SCRIPT_UNDER_TEST="$(cd "$(dirname "$0")/../.." && pwd)/scripts/restart-with-continuation.sh"
OPENCODE_BIN="${OPENCODE_BIN:-$HOME/.opencode/bin/opencode}"
TESTUNIT="cr-test.service"
AUTH="opencode:regression-test-pass"
PROMPT_MARK="Continue exactly where you left off"

STATE_DIR="${TMPDIR:-/tmp}/opencode/regression-continuation"
mkdir -p "$STATE_DIR"
PIDFILE="$STATE_DIR/029-crash-resume-once.pids"   # lines: <server-pid>
WORKFILE="$STATE_DIR/029-crash-resume-once.work"  # scratch dir to rm
: > "$PIDFILE"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/opencode/crash-resume-once.XXXXXX")"
printf '%s\n' "$WORK" > "$WORKFILE"
TEST_STATE="$WORK/state"          # isolated restart-continuations state
CONT="$TEST_STATE/restart-continuations"
ENVFILE="$WORK/test.env"
printf 'OPENCODE_SERVER_PASSWORD=regression-test-pass\n' > "$ENVFILE"

cleanup() {
    if [[ -s "$PIDFILE" ]]; then
        while IFS= read -r pid; do
            [[ "$pid" =~ ^[0-9]+$ ]] || continue
            kill -TERM "$pid" 2>/dev/null || true
            for _ in 1 2 3 4 5 6 7 8 9 10; do
                kill -0 "$pid" 2>/dev/null || break
                sleep 0.2
            done
            kill -0 "$pid" 2>/dev/null && kill -KILL "$pid" 2>/dev/null || true
        done < "$PIDFILE"
    fi
    rm -rf "$WORK"
    : > "$PIDFILE"
}
trap cleanup EXIT

command -v python3 >/dev/null 2>&1 || { echo "FAIL: python3 required"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "FAIL: jq required"; exit 1; }
[[ -x "$OPENCODE_BIN" ]] || { echo "FAIL: opencode binary not executable: $OPENCODE_BIN"; exit 1; }

PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')"
URL="http://127.0.0.1:$PORT"

# Scratch serve instance (session hygiene: scratch cwd only; session
# directory = server cwd, so the created session lives in $WORK).
(cd "$WORK" && OPENCODE_SERVER_PASSWORD=regression-test-pass setsid \
    "$OPENCODE_BIN" serve --hostname 127.0.0.1 --port "$PORT" \
    > "$WORK/serve.log" 2>&1 &)
# Resolve the server PID from the listening-socket owner: under bash, `$!` after
# a backgrounded `cd && ...` list is a wrapper subshell, NOT the serve process
# (a TERM to the wrapper would leave the real server orphaned).
SERVER_PID=""
for _ in $(seq 1 100); do
    SERVER_PID="$(ss -ltnp 2>/dev/null | grep ":$PORT " | grep -oE 'pid=[0-9]+' | head -1 | cut -d= -f2 || true)"
    if [[ -n "$SERVER_PID" ]]; then break; fi
    sleep 0.3
done
printf '%s\n' "$SERVER_PID" >> "$PIDFILE"

# Wait for readiness (authenticated /session/status).
ready=0
for _ in $(seq 1 100); do
    kill -0 "$SERVER_PID" 2>/dev/null || break
    if curl -sS -f --connect-timeout 1 --max-time 2 -u "$AUTH" \
        "$URL/session/status?directory=$(python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1],safe=''))" "$WORK")" \
        > /dev/null 2>&1; then
        ready=1; break
    fi
    sleep 0.3
done
if [[ $ready -ne 1 ]]; then
    echo "FAIL: scratch opencode serve not ready on :$PORT (log: $WORK/serve.log)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    exit 1
fi

# One real session in the scratch instance.
SID="$(curl -sS -f --max-time 5 -u "$AUTH" -X POST "$URL/session" \
    -H 'Content-Type: application/json' -d '{}' | jq -r '.id')"
[[ "$SID" == ses_* ]] || { echo "FAIL: session creation returned id='$SID'"; exit 1; }
sleep 2  # freshness guard: checkpoint must be ≥1s newer than the session's time.updated

# Seed the periodic checkpoint exactly as `checkpoint` would write it.
CKPT_UUID="$(python3 -c 'import uuid; print(uuid.uuid4())')"
CKPT_CREATED="$(date +%s)"
mkdir -p "$CONT"
python3 - "$CONT/last-busy-$TESTUNIT.json" "$CKPT_UUID" "$CKPT_CREATED" "$SID" "$WORK" <<'PY'
import json, sys
out, uid, created, sid, work = sys.argv[1:6]
json.dump({"uuid": uid, "created": int(created),
           "sessions": [{"id": sid, "title": "regression crash-resume", "directory": work}]},
          open(out, "w"), indent=1)
PY

HOOKS_LOG="$CONT/hooks.log"

count_prompt_marks() {
    local body
    body="$(curl -sS --max-time 5 -u "$AUTH" \
        "$URL/session/$SID/message?directory=$(python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1],safe=''))" "$WORK")" \
        2>/dev/null || true)"
    printf '%s\n' "$body" | grep -o "$PROMPT_MARK" | wc -l || true
}

# --- Run 1: crash-class resume must inject exactly one prompt ----------------
set +e
CONTINUATION_JOURNAL_TAG=restart-continuation-test XDG_STATE_DIR="$TEST_STATE" timeout 90 bash "$SCRIPT_UNDER_TEST" \
    hook-resume "$TESTUNIT" "$URL" "$ENVFILE" > "$WORK/resume1.out" 2>&1
RC1=$?
set -e

MARKER="$CONT/.consumed-$TESTUNIT-$CKPT_UUID"
n1=-1
for _ in $(seq 1 50); do  # prompt_async records the message asynchronously
    n1="$(count_prompt_marks)"
    if (( n1 >= 1 )); then break; fi
    sleep 0.3
done

if [[ $RC1 -eq 0 && "$n1" -eq 1 && -e "$MARKER" ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "PASS (a): run 1 injected exactly 1 prompt (rc=$RC1), marker $(basename "$MARKER") created"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "FAIL (a): run 1 rc=$RC1 prompts=$n1 marker=$([[ -e $MARKER ]] && echo yes || echo missing) (resume1.out follows)"
    sed 's/^/    /' "$WORK/resume1.out" >&2 || true
fi

# --- Run 2: second invocation must inject NOTHING ---------------------------
sleep 1
set +e
CONTINUATION_JOURNAL_TAG=restart-continuation-test XDG_STATE_DIR="$TEST_STATE" timeout 30 bash "$SCRIPT_UNDER_TEST" \
    hook-resume "$TESTUNIT" "$URL" "$ENVFILE" > "$WORK/resume2.out" 2>&1
RC2=$?
set -e
sleep 1
n2="$(count_prompt_marks)"

if [[ $RC2 -eq 0 && "$n2" -eq 1 && "$(grep -c 'already consumed' "$HOOKS_LOG")" -ge 1 ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "PASS (b): run 2 injected 0 new prompts (total still $n2), 'already consumed' logged"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "FAIL (b): run 2 rc=$RC2 total-prompts=$n2 (expected 1), already-consumed log lines: $(grep -c 'already consumed' "$HOOKS_LOG" 2>/dev/null || echo 0)"
    sed 's/^/    /' "$WORK/resume2.out" >&2 || true
fi

if [[ $TESTS_FAILED -gt 0 ]]; then
    echo "FAILURE: crash-class resume not exactly-once (see $0)"
    exit 1
fi
echo "PASS: crash-class resume injected exactly once; second run was a no-op"
