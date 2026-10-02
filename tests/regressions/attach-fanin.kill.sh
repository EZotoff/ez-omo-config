#!/usr/bin/env bash
# attach-fanin.kill.sh — cleanup for attach-fanin.sh: deletes only the recorded
# throwaway session and any leftover capture curl. Never touches operator sessions.
set -uo pipefail
EV=$(ls -dt /tmp/opencode/attachfanin.* 2>/dev/null | head -1)
if [[ -n "${EV:-}" && -f "$EV/session.id" ]]; then
  SID=$(cat "$EV/session.id")
  URL="${GATE_URL_3030:-http://127.0.0.1:3030}"
  AUTH_ENV="${GATE_AUTH_ENV_3030:-$HOME/.config/opencode/serve-interactive.env}"
  username=opencode; password=""
  [[ -f "$AUTH_ENV" ]] && { while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in OPENCODE_SERVER_USERNAME=*) username="${line#*=}" ;; OPENCODE_SERVER_PASSWORD=*) password="${line#*=}" ;; esac
  done < "$AUTH_ENV"; }
  auth_args=(); [[ -n "$password" ]] && auth_args=(-u "$username:$password")
  # Abort any in-flight turn first — a live DELETE orphans the turn's
  # message/part writes and FK-fails them (Error · New session toasts,
  # 2026-10-02 incident). If it stays busy past the bounded wait, leave the
  # session in place instead of deleting mid-turn (sweeper soft-archives it).
  curl -s "${auth_args[@]}" --max-time 3 -X POST \
    "$URL/session/$SID/abort?directory=/tmp/opencode/attachfanin-busy" -o /dev/null || true
  busy_ok=1
  for _ in $(seq 1 60); do
    busy="$(curl -s "${auth_args[@]}" --max-time 2 \
      "$URL/session/status?directory=/tmp/opencode/attachfanin-busy" 2>/dev/null \
      | jq -r --arg s "$SID" '.[$s].type // "idle"' 2>/dev/null)"
    [[ "$busy" != "busy" && "$busy" != "retry" ]] && { busy_ok=0; break; }
    sleep 1
  done
  if (( busy_ok == 0 )); then
    curl -s "${auth_args[@]}" -X DELETE "$URL/session/$SID?directory=/tmp/opencode/attachfanin-busy" -o /dev/null
    echo "deleted $SID"
  else
    echo "SKIPPED delete of $SID (still busy after abort + 60s) — left for throwaway sweeper"
  fi
fi
pkill -f "curl -sN.*attachfanin" 2>/dev/null
rm -rf /tmp/opencode/attachfanin.* /tmp/opencode/attachfanin-busy 2>/dev/null
echo "cleanup done"
