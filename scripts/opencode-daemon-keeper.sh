#!/usr/bin/env bash
# Daemon keeper for the OpenCode serve daemons (interactive + bench).
#
# Recovers each unit in UNITS after it was left dead or hung. The recurring
# failure mode: an agent-run update/patch procedure stops the daemon and dies
# before its restart step (2026-09-13/14, 2026-09-21 incidents). systemd's
# Restart= cannot help there — an explicit `systemctl stop` is always honored;
# a probe timer is the only mechanism that covers this failure class.
#
# Safety: two consecutive failed probes (4s apart) are required before any
# action, so a transient load spike cannot get a healthy daemon (and its live
# attached sessions) restarted. Escalation is start → restart (restart only
# when the unit is active-but-unreachable). Always exits 0 so the timer unit
# never shows as failed (house pattern, cf. wal-checkpoint.py).
set -euo pipefail

PORTS_FILE="$HOME/.sisyphus/ports.json"

# Entries: "unit|fallback-port|ports.json-service-key".
# The port is resolved at runtime from ports.json keyed on the service name;
# the fallback literal covers the window before the allocation entry lands.
UNITS=(
  "opencode-interactive.service|3030|opencode-serve-interactive"
  # Fallback 3040 mirrors the ports.json allocation (service:
  # opencode-serve-bench, allocated 2026-09-21); runtime resolution supersedes
  # it if the allocation moves.
  "opencode-bench.service|3040|opencode-serve-bench"
)

resolve_port() {
  local service_key="$1" fallback="$2" out
  out="$(python3 -c '
import json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    for port, entry in data.get("ports", {}).items():
        if entry.get("service") == sys.argv[2]:
            print(port)
            break
except Exception:
    pass
' "$PORTS_FILE" "$service_key" 2>/dev/null || true)"
  echo "${out:-$fallback}"
}

probe() { curl -s -o /dev/null --connect-timeout 2 --max-time 5 "$1"; }

for entry in "${UNITS[@]}"; do
  IFS='|' read -r unit fallback service_key <<<"$entry"
  port="$(resolve_port "$service_key" "$fallback")"
  url="http://127.0.0.1:${port}"
  if ! systemctl --user cat "$unit" &>/dev/null; then
    echo "keeper: ${unit} not installed — skipping"
    continue
  fi


  if probe "$url"; then
    continue
  fi
  sleep 4
  if probe "$url"; then
    echo "keeper: :${port} probe #1 failed, probe #2 OK (transient) — no action"
    continue
  fi

  state="$(systemctl --user is-active "$unit" 2>/dev/null || true)"
  if [[ "$state" == "active" ]]; then
    echo "keeper: :${port} unreachable but unit active — restarting ${unit}"
    systemctl --user restart "$unit"
  else
    echo "keeper: :${port} down (unit state: ${state:-unknown}) — starting ${unit}"
    systemctl --user start "$unit"
  fi

  recovered=0
  for ((i = 1; i <= 24; i++)); do
    if probe "$url"; then
      echo "keeper: :${port} recovered"
      recovered=1
      break
    fi
    sleep 0.5
  done
  if ((recovered == 0)); then
    echo "keeper: :${port} still unreachable after action — check: journalctl --user -u ${unit}"
  fi
done

exit 0
