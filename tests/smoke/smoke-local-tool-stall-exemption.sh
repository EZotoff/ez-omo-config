#!/usr/bin/env bash
# Smoke: local-tool stall exemption (plan: local-tool-stall-exemption, task 7).
#
# The stream-stall watchdog measures time since the last LLM stream event. The
# AI SDK executes local tools inside that same stream, so a legitimately running
# local bash tool looks like provider silence. This smoke drives the bash tool
# through `opencode run` with a reduced stall window and asserts the polarity:
#
#   --expect stall  PASS iff `LLM stream stalled for <stall-ms>ms` is observed
#                   while the local tool is in flight. On an unpatched binary
#                   (live 1.18.31-p3) this reproduces the defect (RED).
#   --expect clean  PASS iff that literal is NOT observed, the sleep tool part
#                   ran to completion, and wall time exceeded the tool duration.
#                   On a patched binary (1.18.31-p4) the local-tool heartbeat
#                   keeps the watchdog from firing (GREEN).
#
# Detection notes (why not just grep stdout):
#   The watchdog failure is retryable, so `opencode run` only prints the error
#   to stdout when the retry budget is exhausted AND the error event wins the
#   race against the idle event. The failure is, however, always persisted on
#   the assistant message in the session store, and it always interrupts the
#   in-flight tool at ~stall-ms. This script therefore treats the stall as
#   observed when ANY of these hold:
#     (a) the literal appears in the run output (stdout+stderr),
#     (b) the literal appears in the session transcript (message store),
#     (c) a `sleep <tool-seconds>` bash tool part was interrupted before
#         completing (duration < tool-seconds) — the direct watchdog signature.
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
OPENCODE_DB="${OPENCODE_DB:-$HOME/.local/share/opencode/opencode.db}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --bin) BIN="${2:?--bin requires a value}"; shift 2 ;;
        --expect) EXPECT="${2:?--expect requires a value}"; shift 2 ;;
        --stall-ms) STALL_MS="${2:?--stall-ms requires a value}"; shift 2 ;;
        --tool-seconds) TOOL_SECONDS="${2:?--tool-seconds requires a value}"; shift 2 ;;
        --model) MODEL="${2:?--model requires a value}"; shift 2 ;;
        --run-timeout) RUN_TIMEOUT_S="${2:?--run-timeout requires a value}"; shift 2 ;;
        -h|--help) sed -n '2,32p' "$0"; exit 0 ;;
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
if ! command -v python3 >/dev/null 2>&1; then
    echo "FAIL: python3 is required" >&2
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
STALL_IN_OUTPUT=0
if grep -qF "$STALL_LITERAL" "$COMBINED"; then
    STALL_IN_OUTPUT=1
fi

# Parse the JSON event stream: session id + `sleep <tool-seconds>` bash parts.
VARS="$SCRATCH/vars"
python3 - "$JSON_LOG" "$TOOL_SECONDS" "$STALL_LITERAL" "$OPENCODE_DB" > "$VARS" <<'PY'
import json, os, shlex, sqlite3, sys

json_path, tool_seconds, stall_literal, db_path = sys.argv[1:5]
tool_ms = int(tool_seconds) * 1000

session_id = ""
found = 0
completed = 0
min_dur = -1
max_dur = -1
for line in open(json_path, encoding="utf-8", errors="replace"):
    line = line.strip()
    if not line:
        continue
    try:
        event = json.loads(line)
    except Exception:
        continue
    if not session_id and event.get("sessionID"):
        session_id = str(event["sessionID"])
    if event.get("type") != "tool_use":
        continue
    part = event.get("part", {})
    if part.get("tool") != "bash":
        continue
    state = part.get("state", {})
    cmd = state.get("input", {}).get("command", "")
    if f"sleep {tool_seconds}" not in cmd:
        continue
    found = 1
    timing = state.get("time", {})
    dur = (timing.get("end") or 0) - (timing.get("start") or 0)
    if dur > 0:
        min_dur = dur if min_dur < 0 else min(min_dur, dur)
        max_dur = max(max_dur, dur)
    if state.get("status") == "completed" and dur >= tool_ms:
        completed = 1

transcript_stall = 0
transcript_msg = ""
if session_id and os.path.exists(db_path):
    try:
        con = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
        cur = con.cursor()
        cur.execute(
            "SELECT data FROM message WHERE session_id=? AND data LIKE ?",
            (session_id, f"%{stall_literal}%"),
        )
        row = cur.fetchone()
        if row:
            transcript_stall = 1
            try:
                transcript_msg = json.loads(row[0]).get("error", {}).get("data", {}).get("message", "")
            except Exception:
                transcript_msg = stall_literal
        con.close()
    except Exception:
        transcript_stall = 0

print(f"SESSION_ID={session_id}")
print(f"SLEEP_TOOL_FOUND={found}")
print(f"SLEEP_TOOL_COMPLETED={completed}")
print(f"SLEEP_TOOL_MIN_DUR={min_dur}")
print(f"SLEEP_TOOL_MAX_DUR={max_dur}")
print(f"STALL_IN_TRANSCRIPT={transcript_stall}")
print(f"TRANSCRIPT_MSG={shlex.quote(transcript_msg)}")
PY
# shellcheck disable=SC1090
source "$VARS"

# (c) direct watchdog signature: the sleep tool was interrupted before it could
# finish (the watchdog aborts the in-flight tool at ~stall-ms).
WATCHDOG_INTERRUPTED=0
if [[ "${SLEEP_TOOL_MIN_DUR:--1}" -gt 0 && "${SLEEP_TOOL_MIN_DUR:--1}" -lt $(( TOOL_SECONDS * 1000 )) ]]; then
    WATCHDOG_INTERRUPTED=1
fi

STALL_SEEN=0
if [[ $STALL_IN_OUTPUT -eq 1 || "${STALL_IN_TRANSCRIPT:-0}" -eq 1 || $WATCHDOG_INTERRUPTED -eq 1 ]]; then
    STALL_SEEN=1
fi

echo "smoke-local-tool-stall-exemption: expect=$EXPECT stall_seen=$STALL_SEEN stall_output=$STALL_IN_OUTPUT stall_transcript=${STALL_IN_TRANSCRIPT:-0} watchdog_interrupted=$WATCHDOG_INTERRUPTED sleep_found=${SLEEP_TOOL_FOUND:-0} sleep_completed=${SLEEP_TOOL_COMPLETED:-0} sleep_min_dur=${SLEEP_TOOL_MIN_DUR:--1} sleep_max_dur=${SLEEP_TOOL_MAX_DUR:--1} wall_ms=$WALL_MS run_rc=$RUN_RC session=${SESSION_ID:-none}"

if [[ "$EXPECT" == "stall" ]]; then
    if [[ $STALL_SEEN -eq 1 ]]; then
        if [[ -n "${TRANSCRIPT_MSG:-}" ]]; then
            echo "stall evidence (transcript): $TRANSCRIPT_MSG"
        fi
        grep -F "$STALL_LITERAL" "$COMBINED" | head -3 || true
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
    echo "FAIL (clean): sleep tool part did not run to completion (found=${SLEEP_TOOL_FOUND:-0}, max_dur=${SLEEP_TOOL_MAX_DUR:--1}, run_rc=$RUN_RC)" >&2
    exit 1
fi
if [[ $WALL_MS -le $(( TOOL_SECONDS * 1000 )) ]]; then
    echo "FAIL (clean): wall time ${WALL_MS}ms not > ${TOOL_SECONDS}s" >&2
    exit 1
fi
echo "PASS (clean): no stall, sleep tool completed (max_dur=${SLEEP_TOOL_MAX_DUR}ms), wall ${WALL_MS}ms > ${TOOL_SECONDS}s"
exit 0
