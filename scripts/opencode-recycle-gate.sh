#!/usr/bin/env bash
# opencode-recycle-gate.sh — quiesce-gated memory recycle for the OpenCode servers.
#
# Replaces the fixed 6h RuntimeMaxSec interrupt factory (wave A, plan
# .omo/plans/continuation-fp-wave-a.md T4): restart a unit ONLY when
#   (a) its cgroup RSS is at/above the recycle threshold, AND
#   (b) it has ZERO busy/retry sessions — counted with PER-DIRECTORY probes
#       (/session/status is instance-scoped; a bare call covers only the root
#       dir and would miss busy sessions elsewhere — Momus R1 fix), AND
#   (c) ENFORCE mode is on.
# OBSERVE=1 (default, set in the systemd unit): log the decision, never restart.
# A restart here is session-safe by construction: the continuation drop-ins
# snapshot/resume around every unit stop/start.
#
# Usage: opencode-recycle-gate.sh [unit[:threshold_bytes] ...]
#   Default units: opencode.service:3221225472 (3G)
#                  opencode-interactive.service:5368709120 (5G)
#   Both thresholds sit BELOW the units' MemoryHigh (4G / 6G): the gate fires
#   before throttling, MemoryHigh remains the backstop.
#
# Env: OBSERVE=1|0, GATE_LOG (default $STATE_DIR/recycle-gate.log),
#      CONTINUATION_DB_PATH (session DB override, read-only),
#      OPENCODE_SERVER_USERNAME (default opencode)

set -euo pipefail

STATE_DIR="${XDG_STATE_DIR:-$HOME/.local/share/opencode}/restart-continuations"
GATE_LOG="${GATE_LOG:-$STATE_DIR/recycle-gate.log}"
DB_PATH="${CONTINUATION_DB_PATH:-$HOME/.local/share/opencode/opencode.db}"
USERNAME="${OPENCODE_SERVER_USERNAME:-opencode}"
OBSERVE="${OBSERVE:-1}"
MAX_AGE_SECONDS=86400   # directory discovery window (matches restart-with-continuation.sh)

auth_password_for() { # <unit> — read the unit's own env file (authoritative)
  case "$1" in
    opencode-interactive.service) env_file="$HOME/.config/opencode/serve-interactive.env" ;;
    opencode-bench.service)       env_file="$HOME/.config/opencode/serve-bench.env" ;;
    *)                            env_file="$HOME/.config/opencode/serve.env" ;;
  esac
  # NOTE: stdout of this function is the password ONLY — never call url_for here
  # (its echo would pollute the captured value and break curl auth).
  [[ -r "$env_file" ]] && grep '^OPENCODE_SERVER_PASSWORD=' "$env_file" | cut -d= -f2- || true
}

url_for() {
  case "$1" in
    opencode-interactive.service) echo "http://127.0.0.1:3030" ;;
    opencode-bench.service)       echo "http://127.0.0.1:3040" ;;
    *)                            echo "http://127.0.0.1:3021" ;;
  esac
}

cgroup_rss_bytes() { # <unit> — 0 when unreadable (caller skips the unit)
  local cg
  cg="$(systemctl --user show -p ControlGroup --value "$1" 2>/dev/null)" || return 0
  [[ -n "$cg" && -r "/sys/fs/cgroup${cg}/memory.current" ]] || return 0
  cat "/sys/fs/cgroup${cg}/memory.current"
}

discover_dirs() { # recently-updated dirs from the shared DB (read-only), /tmp excluded
  MAX_AGE="$MAX_AGE_SECONDS" python3 - "$DB_PATH" <<'PYEOF'
import os, sqlite3, sys, time
db = sys.argv[1]
try:
    con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
except sqlite3.Error:
    sys.exit(0)
cutoff = (time.time() - float(os.environ["MAX_AGE"])) * 1000
try:
    rows = con.execute(
        "select distinct directory from session "
        "where time_updated >= ? and time_archived is null and directory != '' "
        "and directory not like '/tmp/%'", (cutoff,))
    print("\n".join(sorted(r[0] for r in rows)))
except sqlite3.Error:
    pass
PYEOF
}

busy_retry_count() { # <url> <password> — per-directory probe; -1 = probe failure (fail-closed: never restart)
  local url="$1" pass="$2" dirs d enc st n=0
  dirs="$(discover_dirs)" || return -1
  [[ -n "$dirs" ]] || return 0
  while IFS= read -r d; do
    [[ -n "$d" ]] || continue
    enc="$(python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1], safe=''))" "$d")"
    st="$(curl -sS -f --connect-timeout 2 --max-time 5 -u "$USERNAME:$pass" \
          "$url/session/status?directory=$enc" 2>/dev/null)" || return -1
    n=$((n + $(printf '%s' "$st" | python3 -c '
import json,sys
try:
    data=json.load(sys.stdin)
    print(sum(1 for v in data.values() if isinstance(v,dict) and v.get("type") in ("busy","retry")))
except Exception:
    sys.exit(1)' ) )) || return -1
  done <<< "$dirs"
  echo "$n"
}

log_decision() { # <unit> <rss> <threshold> <busy> <decision>
  mkdir -p "$STATE_DIR"
  printf '%s unit=%s rss=%s threshold=%s busy=%s decision=%s\n' \
    "$(date +%Y-%m-%dT%H:%M:%S)" "$1" "$2" "$3" "$4" "$5" >> "$GATE_LOG"
}

main() {
  local specs=("${@:-opencode.service:3221225472 opencode-interactive.service:5368709120}")
  [[ ${#@} -eq 0 ]] && specs=(opencode.service:3221225472 opencode-interactive.service:5368709120)
  for spec in "${specs[@]}"; do
    local unit="${spec%%:*}" threshold="${spec##*:}"
    systemctl --user is-active --quiet "$unit" || continue
    local rss busy pass
    rss="$(cgroup_rss_bytes "$unit")"
    [[ -n "$rss" && "$rss" -gt 0 ]] || { log_decision "$unit" unreadable "$threshold" - skip-no-rss; continue; }
    pass="$(auth_password_for "$unit")"
    [[ -n "$pass" ]] || { log_decision "$unit" "$rss" "$threshold" - skip-no-auth; continue; }
    busy="$(busy_retry_count "$(url_for "$unit")" "$pass")" || busy=-1
    if (( busy < 0 )); then
      log_decision "$unit" "$rss" "$threshold" probe-failed defer-probe-failed   # fail-closed
      continue
    fi
    if (( rss >= threshold )); then
      if (( busy == 0 )); then
        if [[ "$OBSERVE" == "1" ]]; then
          log_decision "$unit" "$rss" "$threshold" "$busy" would-fire-observe
        else
          log_decision "$unit" "$rss" "$threshold" "$busy" restart
          systemctl --user restart "$unit"
        fi
      else
        log_decision "$unit" "$rss" "$threshold" "$busy" defer-busy
      fi
    else
      log_decision "$unit" "$rss" "$threshold" "$busy" below-threshold
    fi
  done
}

main "$@"
