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
  curl -s "${auth_args[@]}" -X DELETE "$URL/session/$SID?directory=/tmp/opencode/attachfanin-busy" -o /dev/null
  echo "deleted $SID"
fi
pkill -f "curl -sN.*attachfanin" 2>/dev/null
rm -rf /tmp/opencode/attachfanin.* /tmp/opencode/attachfanin-busy 2>/dev/null
echo "cleanup done"
