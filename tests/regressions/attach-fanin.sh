#!/usr/bin/env bash
# attach-fanin.sh — regression pair for opencode--event-scope-attach-congestion.
# Drives one scoped /event subscriber against a scratch-directory busy session and
# asserts the foreign message-class byte ceiling. Pre-fix this measured tens of MB
# (foreign message.updated fan-out); post-fix the subscriber sees ~0 message frames.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EV="$(mktemp -d /tmp/opencode/attachfanin.XXXXXX)"
URL="${GATE_URL_3030:-http://127.0.0.1:3030}"
AUTH_ENV="${GATE_AUTH_ENV_3030:-$HOME/.config/opencode/serve-interactive.env}"
BUSY_DIR="/tmp/opencode/attachfanin-busy"
CEILING_BYTES=100000   # foreign message-class bytes allowed in a 30s capture (post-fix ~0)
CAPTURE_SECONDS=30

username=opencode; password=""
[[ -f "$AUTH_ENV" ]] && { while IFS= read -r line || [[ -n "$line" ]]; do
  case "$line" in OPENCODE_SERVER_USERNAME=*) username="${line#*=}" ;; OPENCODE_SERVER_PASSWORD=*) password="${line#*=}" ;; esac
done < "$AUTH_ENV"; }
auth_args=(); [[ -n "$password" ]] && auth_args=(-u "$username:$password")

cleanup() {
  # Abort the injected turn BEFORE deleting the session: a live DELETE orphans
  # the in-flight message/part writes and FK-fails them (Error · New session
  # toasts in the TUI/Beacon — 2026-10-02 incident). Bounded poll, never a bare
  # sleep-loop without exit.
  if [[ -n "${SID:-}" && "${SID:-}" != "null" ]]; then
    curl -s "${auth_args[@]}" --max-time 3 -X POST \
      "$URL/session/$SID/abort?directory=$BUSY_DIR" -o /dev/null || true
    for _ in $(seq 1 60); do
      busy="$(curl -s "${auth_args[@]}" --max-time 2 \
        "$URL/session/status?directory=$BUSY_DIR" 2>/dev/null \
        | jq -r --arg s "$SID" '.[$s].type // "idle"' 2>/dev/null)"
      [[ "$busy" != "busy" && "$busy" != "retry" ]] && break
      sleep 1
    done
    curl -s "${auth_args[@]}" -X DELETE "$URL/session/$SID?directory=$BUSY_DIR" -o /dev/null || true
  fi
  pkill -f "attachfanin-mark" 2>/dev/null
}
trap cleanup EXIT
mkdir -p "$BUSY_DIR"

SID=$(curl -s "${auth_args[@]}" -X POST "$URL/session?directory=$BUSY_DIR" -H 'content-type: application/json' \
  -d '{"title":"attachfanin-regression"}' | jq -r .id)
[[ -z "$SID" || "$SID" == "null" ]] && { echo "FAIL: cannot create busy session"; exit 1; }
echo "$SID" > "$EV/session.id"

PROMPT='Run this exact bash command as one tool call and nothing else: for i in $(seq 1 12); do echo "iter $i: $(seq $i 800 | sha256sum | cut -c1-12)"; sleep 2; done ; then reply done'
curl -s "${auth_args[@]}" -o /dev/null -X POST "$URL/session/$SID/prompt_async?directory=$BUSY_DIR" \
  -H 'content-type: application/json' \
  -d "$(jq -n --arg p "$PROMPT" '{parts:[{type:"text",text:$p}],model:{providerID:"zai-coding-plan",modelID:"glm-5.3-flash"}}')"

timeout "$CAPTURE_SECONDS" curl -sN "${auth_args[@]}" "$URL/event" > "$EV/sse.raw" 2>/dev/null &
CURL=$!
wait $CURL 2>/dev/null

FOREIGN=$(python3 - "$EV/sse.raw" <<'EOF'
import sys, json
tot = 0
for f in open(sys.argv[1], 'rb').read().split(b"\n\n"):
    if not f.startswith(b"data: "): continue
    try: j = json.loads(f[6:])
    except Exception: continue
    if j.get("type","").startswith("message."): tot += len(f)
print(tot)
EOF
)

echo "foreign message-class bytes in ${CAPTURE_SECONDS}s: $FOREIGN (ceiling $CEILING_BYTES)"
if (( FOREIGN <= CEILING_BYTES )); then
  echo "PASS: attach fan-in scoped (opencode--event-scope-attach-congestion)"
  exit 0
fi
echo "FAIL: foreign message firehose present — S1 scope filter not effective"
exit 1
