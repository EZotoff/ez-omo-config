#!/usr/bin/env bash
# Smoke: stall-catch preserved via mock hanging provider
# (plan: local-tool-stall-exemption, task 8).
#
# Never-masked guard for the local-tool stall-exemption patch: a provider
# that accepts the chat-completions request, sends `200` +
# `content-type: text/event-stream`, and then never writes a byte (a
# first-byte hang) must STILL trigger the stream-stall watchdog. This must
# pass on the unpatched live binary (1.18.31-p3, RED/baseline) AND on the
# patched binary (1.18.31-p4, GREEN) — the exemption must never mask a
# genuinely dead provider stream.
#
# Usage:
#   smoke-stall-catch-preserved.sh --bin <opencode-binary> \
#       [--port 18270] [--stall-ms 15000] [--run-timeout 280]
#
# Detection notes (measured on 1.18.31-p3): the stall error is RETRYABLE.
# The watchdog aborts each attempt at ~stall-ms and the session retry loop
# (RETRY_MAX_RETRIES=5, exponential backoff 2s*2^n) keeps retrying — each
# attempt hangs again on the mock. The literal `LLM stream stalled for
# <stall-ms>ms` only surfaces in the run output once the retry budget is
# exhausted (~150-160s wall for 15s stalls: 6 attempts + backoff). The
# direct mid-run signature is the mock server log: a second POST arriving
# ~stall-ms after the first proves the watchdog aborted attempt 1.
#
# Port procedure (deployment skill): the mock server binds a port from the
# reserved `stall-smoke` range (18270-18279, ~/.sisyphus/ports.json). The
# script registers the per-run port entry before binding and releases it on
# exit. The server is always torn down by its recorded PID — never by a
# substring pkill.
#
# The probe is throwaway: it runs from a fresh scratch dir under
# /tmp/opencode (session attachment hygiene) and removes it on exit.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib-smoke.sh
source "$HERE/lib-smoke.sh"

PORTS_REGISTRY="${PORTS_REGISTRY:-$HOME/.sisyphus/ports.json}"
PORT=18270
STALL_MS=15000
RUN_TIMEOUT_S=280
BIN=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --bin) BIN="${2:?--bin requires a value}"; shift 2 ;;
        --port) PORT="${2:?--port requires a value}"; shift 2 ;;
        --stall-ms) STALL_MS="${2:?--stall-ms requires a value}"; shift 2 ;;
        --run-timeout) RUN_TIMEOUT_S="${2:?--run-timeout requires a value}"; shift 2 ;;
        -h|--help) sed -n '2,34p' "$0"; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

if [[ -z "$BIN" ]]; then
    echo "FAIL: --bin is required" >&2
    exit 2
fi
if ! smoke_require_binary "$BIN"; then
    echo "FAIL: binary missing or not executable: $BIN" >&2
    exit 1
fi
if (( PORT < 18270 || PORT > 18279 )); then
    echo "FAIL: --port $PORT outside reserved stall-smoke range 18270-18279" >&2
    exit 2
fi

# --- port registry (reserve per-run entry; release on exit) ----------------

ports_register() {
    jq --argjson p "$PORT" --arg d "$(date +%F)" '
        .ranges["stall-smoke"] = (.ranges["stall-smoke"] // {
            start: 18270, end: 18279,
            allocated: "2026-10-09",
            contact: "ezotoff"
        })
        | .ports[($p | tostring)] = {
            service: "mockstall-hanging-provider",
            project: "stall-smoke",
            allocated: $d
        }' "$PORTS_REGISTRY" > "$PORTS_REGISTRY.tmp" \
        && mv "$PORTS_REGISTRY.tmp" "$PORTS_REGISTRY"
}

ports_release() {
    jq --argjson p "$PORT" 'del(.ports[($p | tostring)])' "$PORTS_REGISTRY" \
        > "$PORTS_REGISTRY.tmp" 2>/dev/null \
        && mv "$PORTS_REGISTRY.tmp" "$PORTS_REGISTRY" || rm -f "$PORTS_REGISTRY.tmp"
}

if [[ ! -f "$PORTS_REGISTRY" ]]; then
    echo "FAIL: port registry missing: $PORTS_REGISTRY (deployment skill required)" >&2
    exit 1
fi
if ss -tuln 2>/dev/null | grep -q ":${PORT} "; then
    echo "FAIL: port $PORT already has a listener" >&2
    exit 1
fi
ports_register

# --- mock hanging provider --------------------------------------------------

SCRATCH="$(mktemp -d /tmp/opencode/stall-catch.XXXXXX)"
SERVER_PID=""
SERVER_LOG="$SCRATCH/mock-server.log"

cleanup() {
    if [[ -n "$SERVER_PID" ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
        kill "$SERVER_PID" 2>/dev/null || true
        for _ in 1 2 3 4 5; do
            kill -0 "$SERVER_PID" 2>/dev/null || break
            sleep 1
        done
        kill -9 "$SERVER_PID" 2>/dev/null || true
    fi
    if [[ -n "$SERVER_PID" ]]; then
        kill -0 "$SERVER_PID" 2>/dev/null \
            && echo "WARN: mock server PID $SERVER_PID still alive after teardown" >&2 \
            || true
    fi
    ports_release
    rm -rf "$SCRATCH"
    smoke_cleanup
}
trap cleanup EXIT

python3 - "$PORT" > "$SERVER_LOG" 2>&1 <<'PY' &
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

port = int(sys.argv[1])

class HangingHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_POST(self):
        length = int(self.headers.get("content-length") or 0)
        if length:
            self.rfile.read(length)
        # Send only the response head; never write a body byte, never close.
        self.send_response(200)
        self.send_header("content-type", "text/event-stream")
        self.end_headers()
        self.wfile.flush()
        while True:
            time.sleep(3600)

    do_GET = do_POST

    def log_message(self, *args):
        pass

ThreadingHTTPServer(("127.0.0.1", port), HangingHandler).serve_forever()
PY
SERVER_PID=$!

# MUST DO: verify the mock server is actually listening before probing.
LISTEN_OK=0
for _ in $(seq 1 20); do
    kill -0 "$SERVER_PID" 2>/dev/null || break
    CODE="$(curl -s -m 2 -o /dev/null -w '%{http_code}' \
        -X POST -H 'content-type: application/json' -d '{}' \
        "http://127.0.0.1:${PORT}/v1/chat/completions" 2>/dev/null || true)"
    if [[ "$CODE" == "200" ]]; then
        LISTEN_OK=1
        break
    fi
    sleep 0.5
done
if [[ $LISTEN_OK -ne 1 ]]; then
    echo "FAIL: mock server on port $PORT not answering (last code: ${CODE:-none})" >&2
    cat "$SERVER_LOG" >&2 || true
    exit 1
fi
echo "mock hanging provider listening on 127.0.0.1:${PORT} (pid ${SERVER_PID})"

# --- scratch project config (attempt 1: project opencode.json) --------------

cat > "$SCRATCH/opencode.json" <<JSON
{
  "\$schema": "https://opencode.ai/config.json",
  "enabled_providers": ["mockstall"],
  "provider": {
    "mockstall": {
      "npm": "@ai-sdk/openai-compatible",
      "options": {
        "baseURL": "http://127.0.0.1:${PORT}/v1",
        "apiKey": "sk-x"
      },
      "models": {
        "hang": {
          "name": "hang",
          "limit": { "context": 8192, "output": 4096 }
        }
      }
    }
  }
}
JSON
python3 -c "import json; json.load(open('$SCRATCH/opencode.json'))"

# --- probe -------------------------------------------------------------------
#
# Detection note (mirrors smoke-local-tool-stall-exemption.sh): the stall error
# is NOT reliably rendered on the `opencode run` stdout for a first-byte hang —
# the authoritative surface is the session message store (assistant message
# error), reached via the `--format json` event stream's sessionID.

OPENCODE_DB="${OPENCODE_DB:-$HOME/.local/share/opencode/opencode.db}"
OUT_LOG="$SCRATCH/run.json"
ERR_LOG="$SCRATCH/run.err"
STALL_LITERAL="LLM stream stalled for ${STALL_MS}ms"

START_S="$(date +%s)"
set +e
(
    cd "$SCRATCH"
    OPENCODE_STREAM_STALL_MS="$STALL_MS" timeout "$RUN_TIMEOUT_S" \
        "$BIN" run --dir "$SCRATCH" --format json --model mockstall/hang 'hi'
) > "$OUT_LOG" 2> "$ERR_LOG"
RUN_RC=$?
set -e
WALL_S=$(( $(date +%s) - START_S ))

COMBINED="$SCRATCH/combined.log"
cat "$OUT_LOG" "$ERR_LOG" > "$COMBINED" 2>/dev/null || true

# sessionID from the JSON event stream + transcript lookup in the message store.
VARS="$SCRATCH/vars"
python3 - "$OUT_LOG" "$STALL_LITERAL" "$OPENCODE_DB" > "$VARS" <<'PY'
import json, os, sqlite3, sys

json_path, stall_literal, db_path = sys.argv[1:4]

session_id = ""
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

transcript_stall = 0
if session_id and os.path.exists(db_path):
    try:
        con = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
        cur = con.cursor()
        cur.execute(
            "SELECT data FROM message WHERE session_id=? AND data LIKE ?",
            (session_id, f"%{stall_literal}%"),
        )
        transcript_stall = 1 if cur.fetchone() else 0
        con.close()
    except Exception:
        transcript_stall = 0

print(f"SESSION_ID={session_id}")
print(f"STALL_IN_TRANSCRIPT={transcript_stall}")
PY
# shellcheck disable=SC1090
source "$VARS"

STALL_IN_OUTPUT=0
grep -qF "$STALL_LITERAL" "$COMBINED" && STALL_IN_OUTPUT=1

echo "smoke-stall-catch-preserved: run_rc=$RUN_RC wall_s=$WALL_S port=$PORT stall_ms=$STALL_MS stall_output=$STALL_IN_OUTPUT stall_transcript=${STALL_IN_TRANSCRIPT:-0} session=${SESSION_ID:-none}"

if [[ $STALL_IN_OUTPUT -eq 1 || "${STALL_IN_TRANSCRIPT:-0}" -eq 1 ]]; then
    echo "PASS: watchdog fired on first-byte provider hang — '$STALL_LITERAL' observed (stall detection preserved)"
    exit 0
fi

echo "FAIL: '$STALL_LITERAL' NOT observed within ${RUN_TIMEOUT_S}s (run_rc=$RUN_RC, wall_s=$WALL_S)" >&2
echo "--- run output (last 40 lines) ---" >&2
tail -n 40 "$COMBINED" >&2 || true
exit 1
