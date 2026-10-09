#!/usr/bin/env bash
# Regression: hook-snapshot fails fast against a wedged (SIGSTOPped) server.
#
# Contract (plan: crashsafe-continuation-hardening Task 8; 2026-09-21 01:00
# incident): ExecStop's hook-snapshot must NEVER hang on an unresponsive
# server. Against a wedged instance it must, within the bounded hook budget
# (~22s: 10s per-call cap + 2s retry gap + 10s retry — the 2026-10-03
# preflight retry), exit 0 (hook trap contract — failure is signaled by logs,
# not exit code), append an rc= line to hooks.log, and emit a
# restart-continuation journal alert.
#
# RED on the pre-hardening script: api() curl had no --max-time, so the
# preflight GET /session/status blocked forever and systemd's 90s TimeoutStopSec
# SIGKILLed the whole cgroup — six sessions died unresumed.
#
# Fully self-contained: scratch `opencode serve` on a free ephemeral port under
# /tmp/opencode, test-local XDG_STATE_DIR, no live-server probes. The paired
# .kill.sh cleans the scratch server if this script is killed mid-run.
set -euo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/helpers.sh"

SCRIPT_UNDER_TEST="$(cd "$(dirname "$0")/../.." && pwd)/scripts/restart-with-continuation.sh"
OPENCODE_BIN="${OPENCODE_BIN:-$HOME/.opencode/bin/opencode}"
TESTUNIT="wedge-test.service"

STATE_DIR="${TMPDIR:-/tmp}/opencode/regression-continuation"
mkdir -p "$STATE_DIR"
PIDFILE="$STATE_DIR/028-wedge-fastfail.pids"   # lines: <server-pid>
WORKFILE="$STATE_DIR/028-wedge-fastfail.work"  # scratch dir to rm
: > "$PIDFILE"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/opencode/wedge-fastfail.XXXXXX")"
printf '%s\n' "$WORK" > "$WORKFILE"
TEST_STATE="$WORK/state"          # isolated restart-continuations state
ENVFILE="$WORK/test.env"
printf 'OPENCODE_SERVER_PASSWORD=regression-test-pass\n' > "$ENVFILE"

cleanup() {
    if [[ -s "$PIDFILE" ]]; then
        while IFS= read -r pid; do
            [[ "$pid" =~ ^[0-9]+$ ]] || continue
            kill -CONT "$pid" 2>/dev/null || true
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
[[ -x "$OPENCODE_BIN" ]] || { echo "FAIL: opencode binary not executable: $OPENCODE_BIN"; exit 1; }

# Free ephemeral port.
PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')"
URL="http://127.0.0.1:$PORT"

# Scratch serve instance (session hygiene: scratch cwd only).
(cd "$WORK" && OPENCODE_SERVER_PASSWORD=regression-test-pass setsid \
    "$OPENCODE_BIN" serve --hostname 127.0.0.1 --port "$PORT" \
    > "$WORK/serve.log" 2>&1 &)
# Resolve the server PID from the listening-socket owner: under bash, `$!` after
# a backgrounded `cd && ...` list is a wrapper subshell, NOT the serve process —
# SIGSTOP would freeze the wrapper and leave the real server live.
listen_ok=0
SERVER_PID=""
for _ in $(seq 1 100); do
    SERVER_PID="$(ss -ltnp 2>/dev/null | grep ":$PORT " | grep -oE 'pid=[0-9]+' | head -1 | cut -d= -f2 || true)"
    if [[ -n "$SERVER_PID" ]]; then listen_ok=1; break; fi
    sleep 0.3
done
printf '%s\n' "$SERVER_PID" >> "$PIDFILE"
if [[ $listen_ok -ne 1 || -z "$SERVER_PID" ]]; then
    echo "FAIL: scratch opencode serve never listened on :$PORT (log: $WORK/serve.log)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    exit 1
fi

# Wedge: freeze the server exactly like the 01:00 incident.
kill -STOP "$SERVER_PID"

JOURNAL_SINCE="$(date '+%Y-%m-%d %H:%M:%S')"
HOOKS_LOG="$TEST_STATE/restart-continuations/hooks.log"

start_ms="$(date +%s%3N)"
set +e
CONTINUATION_JOURNAL_TAG=restart-continuation-test XDG_STATE_DIR="$TEST_STATE" timeout 35 bash "$SCRIPT_UNDER_TEST" \
    hook-snapshot "$TESTUNIT" "$URL" "$ENVFILE" > "$WORK/hook.out" 2>&1
HOOK_RC=$?
set -e
elapsed_ms=$(( $(date +%s%3N) - start_ms ))

# (a) hook returns promptly — never burns the 90s stop window.
if [[ $HOOK_RC -eq 0 && $elapsed_ms -lt 30000 ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "PASS (a): hook-snapshot returned rc=0 in ${elapsed_ms}ms (<30000ms)"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "FAIL (a): hook-snapshot rc=$HOOK_RC elapsed=${elapsed_ms}ms (need rc=0 <30000ms)"
fi

# (b) failure evidence in hooks.log: rc= line (SIGKILL-proof journal of cause).
if grep -q 'rc=' "$HOOKS_LOG" 2>/dev/null; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "PASS (b): hooks.log records failure rc= ($(grep 'rc=' "$HOOKS_LOG" | tail -1))"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "FAIL (b): no rc= line in $HOOKS_LOG"
fi

# (c) journal alert emitted (operator-visible channel; server is dead, no toast).
if journalctl --user -t restart-continuation-test --since "$JOURNAL_SINCE" 2>/dev/null | grep -q 'stop preflight failed'; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "PASS (c): journal alert 'stop preflight failed' visible since $JOURNAL_SINCE"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "FAIL (c): no restart-continuation journal alert since $JOURNAL_SINCE"
fi

if [[ $TESTS_FAILED -gt 0 ]]; then
    echo "FAILURE: wedged server did not fail fast with evidence (see $0)"
    exit 1
fi
echo "PASS: hook-snapshot failed fast against wedged server (rc logged + journal alert)"
