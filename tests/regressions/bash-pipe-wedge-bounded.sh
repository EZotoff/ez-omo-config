#!/usr/bin/env bash
# Regression: bash tool bounded drain when an escaped child holds the pipe.
#
# Contract (debate: .sisyphus/debates/bash-lifecycle-orphan-wedge/): an escaped
# (setsid) child that inherits the tool's stdout pipe must not wedge the call.
# The call must return after a bounded window (deadline + grace), not wait for
# the escaped child's full sleep. The escaped child is outside the cleanup
# guarantee and is killed by the paired .kill.sh.
#
# RED on 1.18.5 (unpatched): the tool waits for stdio EOF, so it blocks for the
# escaped child's full sleep (30s) despite a 5s timeout. GREEN after the patch:
# bounded drain returns at ~deadline+grace and the escaped child is reported.
#
# The bash tool is only reachable through the model loop, so this drives it via
# `opencode run --format json` (the live binary) and reads the tool part's
# start/end timestamps. The escaped child writes its own PID to a file; the
# paired .kill.sh kills exactly that PID (idempotent, no pkill sweeps).
set -euo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/helpers.sh"

STATE_DIR="${TMPDIR:-/tmp}/opencode/regression-bash-lifecycle"
mkdir -p "$STATE_DIR"
PIDFILE="$STATE_DIR/bash-pipe-wedge-bounded.pids"
: > "$PIDFILE"

OPENCODE_BIN="${OPENCODE_BIN:-$HOME/.opencode/bin/opencode}"
MODEL="${REGRESSION_MODEL:-zai-coding-plan/glm-5.3-flash}"
TIMEOUT_MS="${REGRESSION_TIMEOUT_MS:-5000}"
GRACE_MS="${REGRESSION_GRACE_MS:-10000}"
BOUND_MS=$((TIMEOUT_MS + GRACE_MS))
RUN_TIMEOUT_S="${REGRESSION_RUN_TIMEOUT_S:-120}"
ESCAPED_SLEEP_S="${REGRESSION_ESCAPED_SLEEP_S:-30}"

if [[ ! -x "$OPENCODE_BIN" ]]; then
    echo "FAIL: opencode binary not executable: $OPENCODE_BIN"
    exit 1
fi
command -v python3 >/dev/null 2>&1 || { echo "FAIL: python3 required"; exit 1; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/opencode/regression-bash-wedge.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
JSON="$WORK/run.json"
CHILD_PIDFILE="$WORK/child.pid"

PROMPT="Make exactly TWO separate bash tool calls, sequentially.
Call 1: use timeout=${TIMEOUT_MS}, command: setsid sh -c 'echo \$\$ > ${CHILD_PIDFILE}; exec sleep ${ESCAPED_SLEEP_S}' & echo leader-done .
Call 2 (immediately after call 1 returns): use timeout=${TIMEOUT_MS}, command: echo followup-ok .
After both calls, reply with the single word DONE."

set +e
timeout "$RUN_TIMEOUT_S" "$OPENCODE_BIN" run --format json --model "$MODEL" "$PROMPT" \
    > "$JSON" 2>"$WORK/err.log"
RUN_RC=$?
set -e

if [[ $RUN_RC -ne 0 ]]; then
    echo "FAIL: opencode run exited rc=$RUN_RC (log: $WORK/err.log)"
    tail -5 "$WORK/err.log" >&2 || true
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Record the escaped child PID (if the agent ran the command) so the paired
# .kill.sh can clean the survivor the tool deliberately does not own.
CHILD_PID=""
if [[ -f "$CHILD_PIDFILE" ]]; then
    CHILD_PID="$(tr -dc '0-9' < "$CHILD_PIDFILE")"
    if [[ -n "$CHILD_PID" ]]; then
        printf '%s\n' "$CHILD_PID" >> "$PIDFILE"
    fi
fi

# Parse the bash tool parts: identify the wedging call by its PID-file marker
# and the follow-up by its command text.
VARS="$WORK/vars"
python3 - "$JSON" "$CHILD_PIDFILE" > "$VARS" <<'PY'
import json, sys

json_path, child_pidfile = sys.argv[1], sys.argv[2]
tools = []
for line in open(json_path, encoding="utf-8", errors="replace"):
    line = line.strip()
    if not line:
        continue
    try:
        event = json.loads(line)
    except Exception:
        continue
    if event.get("type") != "tool_use":
        continue
    part = event.get("part", {})
    if part.get("tool") != "bash":
        continue
    state = part.get("state", {})
    timing = state.get("time", {})
    tools.append({
        "cmd": state.get("input", {}).get("command", ""),
        "timeout": state.get("input", {}).get("timeout"),
        "dur": (timing.get("end") or 0) - (timing.get("start") or 0),
    })

wedge = next((t for t in tools if child_pidfile in t["cmd"]), None)
follow = next((t for t in tools if "followup-ok" in t["cmd"]), None)
print(f"TOOL_COUNT={len(tools)}")
print(f"WEDGE_FOUND={1 if wedge else 0}")
print(f"WEDGE_DUR={wedge['dur'] if wedge else -1}")
print(f"WEDGE_TIMEOUT={wedge['timeout'] if wedge else -1}")
print(f"FOLLOWUP_FOUND={1 if follow else 0}")
print(f"FOLLOWUP_DUR={follow['dur'] if follow else -1}")
PY
# shellcheck disable=SC1090
source "$VARS"

# (a) the wedging call returns after a bounded window, not the child's full sleep.
if [[ "${WEDGE_FOUND:-0}" -eq 1 && "${WEDGE_TIMEOUT:-0}" -eq "$TIMEOUT_MS" \
      && "${WEDGE_DUR:-0}" -ge $((TIMEOUT_MS - 500)) && "${WEDGE_DUR:-0}" -le "$BOUND_MS" ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "PASS (a): wedging call returned in ${WEDGE_DUR}ms (deadline ${TIMEOUT_MS}ms, bound ${BOUND_MS}ms, escaped sleep ${ESCAPED_SLEEP_S}s)"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "FAIL (a): wedging call duration ${WEDGE_DUR:-missing}ms not within [${TIMEOUT_MS}ms, ${BOUND_MS}ms] (found=${WEDGE_FOUND:-0}, timeout=${WEDGE_TIMEOUT:-missing})"
fi

# (b) an immediate follow-up command completes in <2s (server not wedged).
if [[ "${FOLLOWUP_FOUND:-0}" -eq 1 && "${FOLLOWUP_DUR:-99999}" -lt 2000 ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "PASS (b): follow-up command completed in ${FOLLOWUP_DUR}ms (<2000ms)"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "FAIL (b): follow-up duration ${FOLLOWUP_DUR:-missing}ms not <2000ms (found=${FOLLOWUP_FOUND:-0})"
fi

if [[ $TESTS_FAILED -gt 0 ]]; then
    echo "FAILURE: escaped pipe holder wedged the bash tool (see tests/regressions/bash-pipe-wedge-bounded.sh)"
    exit 1
fi
echo "PASS: bash tool returned after a bounded drain despite an escaped pipe holder"
