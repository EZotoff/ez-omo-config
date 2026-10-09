#!/usr/bin/env bash
# Smoke: local-tool stall exemption (plan: local-tool-stall-exemption, task 7).
#
# The stream-stall watchdog measures time since the last LLM stream event. The
# AI SDK executes local tools inside that same stream, so a legitimately running
# local bash tool looks like provider silence. This smoke drives the bash tool
# through `opencode run` with a reduced stall window and asserts the polarity:
#
#   --expect stall  PASS iff `LLM stream stalled for <stall-ms>ms` appears in the
#                   run output while the local tool is in flight. On an
#                   unpatched binary (live 1.18.31-p3) this reproduces the
#                   defect (RED).
#   --expect clean  PASS iff that literal does NOT appear, the sleep tool part
#                   completed, and wall time exceeded the tool duration. On a
#                   patched binary (1.18.31-p4) the local-tool heartbeat keeps
#                   the watchdog from firing (GREEN).
#
# Usage:
#   smoke-local-tool-stall-exemption.sh --bin <opencode-binary> \
#       --expect stall|clean [--stall-ms 15000] [--tool-seconds 45] \
#       [--model provider/model] [--run-timeout 280]
#
# The probe is throwaway: it runs from a fresh scratch dir under /tmp/opencode
# (session attachment hygiene) and removes it on exit.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib-smoke.sh
source "$HERE/lib-smoke.sh"

BIN=""
EXPECT=""
STALL_MS=15000
TOOL_SECONDS=45
MODEL=""
RUN_TIMEOUT_S=280

while [[ $# -gt 0 ]]; do
    case "$1" in
        --bin) BIN="${2:?--bin requires a value}"; shift 2 ;;
        --expect) EXPECT="${2:?--expect requires a value}"; shift 2 ;;
        --stall-ms) STALL_MS="${2:?--stall-ms requires a value}"; shift 2 ;;
        --tool-seconds) TOOL_SECONDS="${2:?--tool-seconds requires a value}"; shift 2 ;;
        --model) MODEL="${2:?--model requires a value}"; shift 2 ;;
        --run-timeout) RUN_TIMEOUT_S="${2:?--run-timeout requires a value}"; shift 2 ;;
        -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

if [[ -z "$BIN" ]]; then
    echo "FAIL: --bin is required" >&2
    exit 2
fi
case "$EXPECT" in
    stall|clean) ;;
    *) echo "FAIL: --expect must be stall|clean" >&2; exit 2 ;;
esac
if ! smoke_require_binary "$BIN"; then
    echo "FAIL: binary missing or not executable: $BIN" >&2
    exit 1
fi

SCRATCH="$(mktemp -d /tmp/opencode/local-tool-stall.XXXXXX)"
cleanup() { rm -rf "$SCRATCH"; smoke_cleanup; }
trap cleanup EXIT

JSON_LOG="$SCRATCH/run.json"
ERR_LOG="$SCRATCH/run.err"
COMBINED="$SCRATCH/combined.log"

PROMPT="Use the bash tool exactly once. Set its timeout parameter to 120000 (milliseconds). The command must be exactly: sleep ${TOOL_SECONDS}
Do not run any other command and do not use any other tool. After the command finishes, reply with exactly: SLEEP_DONE"

MODEL_ARGS=()
if [[ -n "$MODEL" ]]; then
    MODEL_ARGS=(--model "$MODEL")
fi

START_MS="$(date +%s%3N)"
set +e
(
    cd "$SCRATCH"
    OPENCODE_STREAM_STALL_MS="$STALL_MS" timeout "$RUN_TIMEOUT_S" \
        "$BIN" run --dir "$SCRATCH" --format json ${MODEL_ARGS[@]+"${MODEL_ARGS[@]}"} "$PROMPT"
) > "$JSON_LOG" 2> "$ERR_LOG"
RUN_RC=$?
set -e
END_MS="$(date +%s%3N)"
WALL_MS=$(( END_MS - START_MS ))

cat "$JSON_LOG" "$ERR_LOG" > "$COMBINED" 2>/dev/null || true

STALL_LITERAL="LLM stream stalled for ${STALL_MS}ms"
STALL_SEEN=0
STALL_EXCERPT=""
if grep -qF "$STALL_LITERAL" "$COMBINED"; then
    STALL_SEEN=1
    STALL_EXCERPT="$(grep -m2 -F "$STALL_LITERAL" "$COMBINED" | tr -d '\\000-\\010\\013\\014\\016-\\037' | head -c 400)"
    echo "stall excerpt: $STALL_EXCERPT"
fi

# Parse the bash tool part for the sleep command from the JSON event stream.
VARS="$SCRATCH/vars"
python3 - "$JSON_LOG" "$TOOL_SECONDS" > "$VARS" <<'PY'
import json, sys

json_path, tool_seconds = sys.argv[1], sys.argv[2]
needle = f"sleep {tool_seconds}"
found = 0
completed = 0
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
    cmd = state.get("input", {}).get("command", "")
    if needle not in cmd:
        continue
    found = 1
    if state.get("status") == "completed":
        completed = 1
print(f"SLEEP_TOOL_FOUND={found}")
print(f"SLEEP_TOOL_COMPLETED={completed}")
PY
# shellcheck disable=SC1090
source "$VARS"

echo "smoke-local-tool-stall-exemption: expect=$EXPECT stall_seen=$STALL_SEEN sleep_found=${SLEEP_TOOL_FOUND:-0} sleep_completed=${SLEEP_TOOL_COMPLETED:-0} wall_ms=$WALL_MS run_rc=$RUN_RC"

if [[ "$EXPECT" == "stall" ]]; then
    if [[ $STALL_SEEN -eq 1 ]]; then
        echo "PASS (stall): watchdog fired during local tool execution — defect reproduced"
        exit 0
    fi
    echo "FAIL (stall): '$STALL_LITERAL' not observed (sleep_found=${SLEEP_TOOL_FOUND:-0}, run_rc=$RUN_RC, wall_ms=$WALL_MS)" >&2
    exit 1
fi

# --expect clean
if [[ $STALL_SEEN -eq 1 ]]; then
    echo "FAIL (clean): watchdog fired during local tool execution — exemption not active" >&2
    exit 1
fi
if [[ "${SLEEP_TOOL_COMPLETED:-0}" -ne 1 ]]; then
    echo "FAIL (clean): sleep tool part did not complete (found=${SLEEP_TOOL_FOUND:-0}, run_rc=$RUN_RC)" >&2
    exit 1
fi
if [[ $WALL_MS -le $(( TOOL_SECONDS * 1000 )) ]]; then
    echo "FAIL (clean): wall time ${WALL_MS}ms not > ${TOOL_SECONDS}s" >&2
    exit 1
fi
echo "PASS (clean): no stall, sleep tool completed, wall ${WALL_MS}ms > ${TOOL_SECONDS}s"
exit 0
