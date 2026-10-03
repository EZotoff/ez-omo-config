#!/usr/bin/env bash
# 032-event-data-compression.sh — regression pair for opencode--event-data-compression.
# Drives a scratch serve (candidate binary, ISOLATED OPENCODE_DB — compressed rows
# must never touch the shared DB while codec-less daemons live), injects a >=8KB
# synthetic prompt, and asserts:
#   1. at least one durable event row is stored gz1:-compressed
#   2. the message read-back path decodes it (server returns the full text)
# Scratch-dir discipline per AGENTS session-hygiene: everything under $WORK.
set -uo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/helpers.sh"

OPENCODE_BIN="${OPENCODE_BIN:-$HOME/.opencode/bin/opencode}"
# Status gate (mirrors the 020 pattern): while the DEFAULT binary predates the
# codec, this pair would fail for the wrong reason — skip until p3 deploys.
# An explicit OPENCODE_BIN (kill.sh, candidate runs) bypasses the gate.
if [[ -z "${OPENCODE_BIN_SET:-}" ]] && [[ "$OPENCODE_BIN" == "$HOME/.opencode/bin/opencode" ]] \
   && ! grep -aq 'OPENCODE_EVENT_CODEC' "$OPENCODE_BIN" 2>/dev/null; then
    echo "SKIP: live binary predates event-data-compression — gate lifts at p3 deploy"
    exit 0
fi
WORK="$(mktemp -d "${TMPDIR:-/tmp}/opencode/event-codec.XXXXXX")"
PIDFILE="$WORK/pid"

cleanup() {
    if [[ -s "$PIDFILE" ]]; then
        kill -TERM "$(cat "$PIDFILE")" 2>/dev/null || true
        for _ in 1 2 3 4 5 6 7 8 9 10; do
            kill -0 "$(cat "$PIDFILE")" 2>/dev/null || break
            sleep 0.2
        done
        kill -0 "$(cat "$PIDFILE")" 2>/dev/null && kill -KILL "$(cat "$PIDFILE")" 2>/dev/null || true
    fi
    rm -rf "$WORK"
}
trap cleanup EXIT

[[ -x "$OPENCODE_BIN" ]] || { echo "FAIL: opencode binary not executable: $OPENCODE_BIN"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "FAIL: python3 required"; exit 1; }

PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')"
URL="http://127.0.0.1:$PORT"
PASS="regression-test-pass"

# Scratch serve: isolated DB via OPENCODE_DB (absolute path per core/database flag),
# codec default-on (no OPENCODE_EVENT_CODEC set).
(cd "$WORK" && env -u OPENCODE_EVENT_CODEC OPENCODE_SERVER_PASSWORD="$PASS" OPENCODE_DB="$WORK/test.db" setsid \
    "$OPENCODE_BIN" serve --hostname 127.0.0.1 --port "$PORT" \
    > "$WORK/serve.log" 2>&1 &)
SERVER_PID=""
for _ in $(seq 1 100); do
    SERVER_PID="$(ss -ltnp 2>/dev/null | grep ":$PORT " | grep -oE 'pid=[0-9]+' | head -1 | cut -d= -f2 || true)"
    [[ -n "$SERVER_PID" ]] && break
    sleep 0.3
done
[[ -n "$SERVER_PID" ]] || { echo "FAIL: scratch serve never listened (log: $WORK/serve.log)"; exit 1; }
echo "$SERVER_PID" > "$PIDFILE"

auth=(-u "opencode:$PASS")
wait_health() {
    for _ in $(seq 1 50); do
        curl -s "${auth[@]}" --max-time 2 -o /dev/null -w '%{http_code}' "$URL/config" 2>/dev/null | grep -q 200 && return 0
        sleep 0.3
    done
    return 1
}
wait_health || { echo "FAIL: scratch serve never healthy"; exit 1; }

# Create session + inject an 8KB synthetic user prompt (LLM-independent: the
# MessageUpdated durable event carries the full text regardless of model outcome).
SID="$(curl -s "${auth[@]}" --max-time 5 -X POST -H 'Content-Type: application/json' \
    -d "{\"directory\":\"$WORK\"}" "$URL/session" | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')"
[[ -n "$SID" && "$SID" != "None" ]] || { echo "FAIL: session create failed"; exit 1; }

BIGTEXT="codec-regression-marker-7f3a $(python3 -c 'print("x"*8192)')"
python3 - "$URL" "$SID" "$WORK" "$BIGTEXT" <<'EOF' >/dev/null 2>&1 || true
import json, sys, urllib.request, base64
url, sid, work, text = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
req = urllib.request.Request(
    f"{url}/session/{sid}/prompt_async?directory={work}",
    data=json.dumps({"parts": [{"type": "text", "text": text}]}).encode(),
    headers={"Content-Type": "application/json"},
    method="POST")
auth = base64.b64encode(b"opencode:regression-test-pass").decode()
req.add_header("Authorization", f"Basic {auth}")
urllib.request.urlopen(req, timeout=5).read()
EOF

# DB poller helper (avoids heredoc-in-command-substitution parse issues)
cat > "$WORK/poll.py" <<'PYEOF'
import sqlite3, sys
try:
    con = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True, timeout=2)
    print(con.execute("SELECT COUNT(*) FROM event WHERE data LIKE 'gz1:%'").fetchone()[0])
except Exception:
    print(0)
PYEOF

# Poll the ISOLATED db for a compressed durable event row (bounded).
gz_rows=0
for _ in $(seq 1 60); do
    gz_rows="$(python3 "$WORK/poll.py" "$WORK/test.db")"
    [[ "$gz_rows" -ge 1 ]] && break
    sleep 0.5
done
if [[ "$gz_rows" -lt 1 ]]; then
    echo "FAIL: no gz1:-compressed event rows in scratch DB (codec not active in $OPENCODE_BIN)"
    exit 1
fi
echo "ok: $gz_rows compressed event row(s) stored"

# Decode-on-read proof: the message list must return the full injected text.
decoded=""
for _ in $(seq 1 30); do
    decoded="$(curl -s "${auth[@]}" --max-time 5 "$URL/session/$SID/message?directory=$WORK" 2>/dev/null || true)"
    echo "$decoded" | grep -q 'codec-regression-marker-7f3a' && break
    sleep 0.5
done
echo "$decoded" | grep -q 'codec-regression-marker-7f3a' \
    && echo "ok: compressed rows decode on read (marker text returned)" \
    || { echo "FAIL: read path did not return the injected text (decode broken?)"; exit 1; }

echo "PASS: 032-event-data-compression"
exit 0
