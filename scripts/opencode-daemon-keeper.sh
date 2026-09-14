#!/usr/bin/env bash
# Daemon keeper for the OpenCode interactive attach daemon (127.0.0.1:3030).
#
# Recovers opencode-interactive.service after it was left dead or hung. The
# recurring failure mode: an agent-run update/patch procedure stops the daemon
# and dies before its restart step (2026-09-13/14 incidents). systemd's
# Restart= cannot help there — an explicit `systemctl stop` is always honored;
# a probe timer is the only mechanism that covers this failure class.
#
# Safety: two consecutive failed probes (4s apart) are required before any
# action, so a transient load spike cannot get a healthy daemon (and its live
# attached sessions) restarted. Escalation is start → restart (restart only
# when the unit is active-but-unreachable). Always exits 0 so the timer unit
# never shows as failed (house pattern, cf. wal-checkpoint.py).
set -euo pipefail

UNIT="opencode-interactive.service"
URL="http://127.0.0.1:3030"

probe() { curl -s -o /dev/null --max-time 2 "$URL"; }

if probe; then
  exit 0
fi
sleep 4
if probe; then
  echo "keeper: probe #1 failed, probe #2 OK (transient) — no action"
  exit 0
fi

state="$(systemctl --user is-active "$UNIT" 2>/dev/null || true)"
if [[ "$state" == "active" ]]; then
  echo "keeper: daemon unreachable but unit active — restarting ${UNIT}"
  systemctl --user restart "$UNIT"
else
  echo "keeper: daemon down (unit state: ${state:-unknown}) — starting ${UNIT}"
  systemctl --user start "$UNIT"
fi

for ((i = 1; i <= 24; i++)); do
  if probe; then
    echo "keeper: ${URL} recovered"
    exit 0
  fi
  sleep 0.5
done

echo "keeper: ${URL} still unreachable after action — check: journalctl --user -u ${UNIT}"
exit 0
