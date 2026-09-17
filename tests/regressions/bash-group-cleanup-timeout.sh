#!/usr/bin/env bash
# Regression: bash tool group cleanup on timeout (contained survivor).
#
# Contract (debate: .sisyphus/debates/bash-lifecycle-orphan-wedge/): a bash tool
# call must not return while a process it spawned is still alive in its own
# process group. Output EOF is NOT quiescence — a contained child that redirects
# its stdio and keeps running must still be cleaned before the call returns.
#
# RED on 1.18.5 (unpatched): the tool returns as soon as the leader's stdio
# closes, leaving the contained `sleep 60` alive and returning far before the
# deadline. GREEN after the supervised-pgroup patch: the call waits for group
# quiescence until the deadline, then TERM->grace->KILL cleans the group.
#
# The bash tool is only reachable through the model loop, so this drives it via
# `opencode run --format json` (the live binary) and reads the tool part's
# start/end timestamps. The contained child writes its own PID to a file; the
# paired .kill.sh kills exactly that PID (idempotent, no pkill sweeps).
set -euo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/helpers.sh"

STATE_DIR="${TMPDIR:-/tmp}/opencode/regression-bash-lifecycle"
mkdir -p "$STATE_DIR"
PIDFILE="$STATE_DIR/bash-group-cleanup-timeout.pids"
: > "$PIDFILE"

OPENCODE_BIN="${OPENCODE_BIN:-$HOME/.opencode/bin/opencode}"
MODEL="${REGRESSION_MODEL:-zai-coding-plan/glm-5.3-flash}"
TIMEOUT_MS="${REGRESSION_TIMEOUT_MS:-5000}"
GRACE_MS="${REGRESSION_GRACE_MS:-10000}"
BOUND_MS=$((TIMEOUT_MS + GRACE_MS))
RUN_TIMEOUT_S="${REGRESSION_RUN_TIMEOUT_S:-120}"

if [[ ! -x "$OPENCODE_BIN" ]]; then
    echo "FAIL: opencode binary not executable: $OPENCODE_BIN"
    exit 1
fi
command -v python3 >/dev/null 2>&1 || { echo "FAIL: python3 required"; exit 1; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/opencode/regression-bash-timeout.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
JSON="$WORK/run.json"
CHILD_PIDFILE="$WORK/child.pid"

PROMPT="Make exactly TWO separate bash tool calls, sequentially.
Call 1: use timeout=${TIMEOUT_MS}, command: sleep 60 >/dev/null 2>&1 & echo \$! > ${CHILD_PIDFILE}; echo leader-done .
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

# Record the contained child PID (if the agent ran the command) so the paired
# .kill.sh can clean a survivor left by the RED (unpatched) binary.
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

# (a) the wedging call returns near deadline+grace (not early, not unbounded).
if [[ "${WEDGE_FOUND:-0}" -eq 1 && "${WEDGE_TIMEOUT:-0}" -eq "$TIMEOUT_MS" \
      && "${WEDGE_DUR:-0}" -ge $((TIMEOUT_MS - 500)) && "${WEDGE_DUR:-0}" -le "$BOUND_MS" ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "PASS (a): wedging call returned in ${WEDGE_DUR}ms (deadline ${TIMEOUT_MS}ms, bound ${BOUND_MS}ms)"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "FAIL (a): wedging call duration ${WEDGE_DUR:-missing}ms not within [${TIMEOUT_MS}ms, ${BOUND_MS}ms] (found=${WEDGE_FOUND:-0}, timeout=${WEDGE_TIMEOUT:-missing})"
fi

# (b) the contained sleep is gone after the call returns.
if [[ -n "$CHILD_PID" ]] && kill -0 "$CHILD_PID" 2>/dev/null; then
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "FAIL (b): contained sleep PID $CHILD_PID still alive after call returned"
else
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "PASS (b): contained sleep PID ${CHILD_PID:-<none>} gone after return"
fi

# (c) an immediate follow-up command completes in <2s.
if [[ "${FOLLOWUP_FOUND:-0}" -eq 1 && "${FOLLOWUP_DUR:-99999}" -lt 2000 ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "PASS (c): follow-up command completed in ${FOLLOWUP_DUR}ms (<2000ms)"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "FAIL (c): follow-up duration ${FOLLOWUP_DUR:-missing}ms not <2000ms (found=${FOLLOWUP_FOUND:-0})"
fi

if [[ $TESTS_FAILED -gt 0 ]]; then
    echo "FAILURE: bash tool left a contained survivor / returned early (see tests/regressions/bash-group-cleanup-timeout.sh)"
    exit 1
fi
echo "PASS: bash tool cleaned the contained group on timeout and follow-up was immediate"
