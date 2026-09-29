#!/usr/bin/env bash
# Refuse a server stop unless every known session directory is idle on all three servers.
# Discovery must be exhaustive: a recently-updated cutoff can miss an old directory
# with a busy session, falsely declare idle, and permit the stop this gate prevents.
# The bench server uses serve-bench.env; if it does not exist, probe 3040 without auth.
# Overrides for isolated tests: GATE_DB_PATH, GATE_URL_3021/3030/3040,
# GATE_AUTH_ENV_3021/3030/3040, GATE_BUDGET_SECONDS (explicit override).
# Default budget after discovery: clamp(ceil(directories * 3 / 12), 120, 900)s.
# KNOWN LIMITATION: stale/nonexistent directories take ~2.5-4s server-side
# (recent directories ~0.4s); 8-parallel waves can hit the 4s curl cap.
# A 892-directory DB needs ~19min, beyond the 900s cap: idle sweeps fail closed.
# Operators may set GATE_BUDGET_SECONDS, prune the session DB, or consciously --force.
# Full sweeps probe three servers per directory; measured throughput is 15-20/s,
# so 12/s leaves headroom where a fixed 120s exhausted before finishing.
# CAMPAIGN_LIVE=1: opt-in live test with 3030 real and the other URLs stubbed;
# never enabled by this script or its default verification.

set -euo pipefail

force=false
case "${1:-}" in
  --force) force=true; shift ;;
  '') ;;
  *) printf 'usage: %s [--force]\n' "$0" >&2; exit 2 ;;
esac
if (( $# )); then printf 'usage: %s [--force]\n' "$0" >&2; exit 2; fi

budget="${GATE_BUDGET_SECONDS:-120}"
if [[ ! "$budget" =~ ^[1-9][0-9]*$ ]]; then
  printf 'GATE_BUDGET_SECONDS must be a positive integer\n' >&2
  exit 2
fi
started=$(date +%s)
deadline=$(( started + budget ))
db="${GATE_DB_PATH:-$HOME/.local/share/opencode/opencode.db}"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
failed=false

remaining=$((deadline - $(date +%s)))
if (( remaining <= 0 )) || ! GATE_DB_PATH="$db" timeout "$remaining" python3 -c '
import os, sqlite3, sys
from pathlib import Path
db = Path(os.environ["GATE_DB_PATH"]).expanduser().resolve()
con = sqlite3.connect(db.as_uri() + "?mode=ro", uri=True)
for (directory,) in con.execute("select distinct directory from session where directory is not null and directory != \x27\x27 order by directory"):
    sys.stdout.buffer.write(os.fsencode(directory) + b"\0")
' > "$tmp/dirs" 2>/dev/null; then
  printf 'cannot establish idleness: session DB unreadable or budget exhausted\n' >&2
  failed=true
elif [[ ! -s "$tmp/dirs" ]]; then
  printf 'cannot establish idleness: no session directories in DB\n' >&2
  failed=true
else
  if [[ -z "${GATE_BUDGET_SECONDS+x}" ]]; then
    n_dirs=$(tr -cd '\000' < "$tmp/dirs" | wc -c)
    budget=$(( (n_dirs * 3 + 11) / 12 ))
    if (( budget < 120 )); then budget=120; fi
    if (( budget > 900 )); then budget=900; fi
    deadline=$(( started + budget ))
  fi
  probe() {
    local server="$1" url="$2" auth_env="$3" directory="$4"
    local username=opencode password='' line status
    if [[ -f "$auth_env" ]]; then
      if [[ ! -r "$auth_env" ]]; then
        printf 'cannot establish idleness: %s auth file unreadable\n' "$server" >&2
        return 1
      fi
      while IFS= read -r line || [[ -n "$line" ]]; do
        case "$line" in
          OPENCODE_SERVER_USERNAME=*) username="${line#*=}" ;;
          OPENCODE_SERVER_PASSWORD=*) password="${line#*=}" ;;
        esac
      done < "$auth_env"
      if [[ -z "$password" ]]; then
        printf 'cannot establish idleness: %s password missing\n' "$server" >&2
        return 1
      fi
      if ! status="$(curl -fsS --connect-timeout 2 --max-time 4 -u "$username:$password" \
        --get --data-urlencode "directory=$directory" "$url/session/status" 2>/dev/null)"; then
        printf 'cannot establish idleness: %s status probe failed\n' "$server" >&2
        return 1
      fi
    else
      if [[ "$server" != opencode-bench.service ]]; then
        printf 'cannot establish idleness: %s auth file missing\n' "$server" >&2
        return 1
      fi
      if ! status="$(curl -fsS --connect-timeout 2 --max-time 4 \
        --get --data-urlencode "directory=$directory" "$url/session/status" 2>/dev/null)"; then
        printf 'cannot establish idleness: %s status probe failed\n' "$server" >&2
        return 1
      fi
    fi
    if ! GATE_DB_PATH="$db" GATE_SERVER="$server" GATE_STATUS="$status" python3 -c '
import json, os, sqlite3, sys
from pathlib import Path
data = json.loads(os.environ["GATE_STATUS"])
if not isinstance(data, dict):
    sys.exit(1)
con = sqlite3.connect(Path(os.environ["GATE_DB_PATH"]).expanduser().resolve().as_uri() + "?mode=ro", uri=True)
for sid, state in data.items():
    if not isinstance(state, dict) or not isinstance(state.get("type"), str):
        sys.exit(1)
    if state["type"] in ("busy", "retry"):
        row = con.execute("select title from session where id = ?", (sid,)).fetchone()
        title = str(row[0]) if row and row[0] else "(unknown)"
        print(os.environ["GATE_SERVER"], sid, state["type"], title.replace("\n", " ").replace("\r", " "))
'; then
      printf 'cannot establish idleness: %s malformed status or DB error\n' "$server" >&2
      return 1
    fi
  }
  export -f probe
  export db
  {
    while IFS= read -r -d '' directory; do
      printf '%s\0%s\0%s\0%s\0' opencode.service "${GATE_URL_3021:-http://127.0.0.1:3021}" \
        "${GATE_AUTH_ENV_3021:-$HOME/.config/opencode/serve.env}" "$directory"
      printf '%s\0%s\0%s\0%s\0' opencode-interactive.service "${GATE_URL_3030:-http://127.0.0.1:3030}" \
        "${GATE_AUTH_ENV_3030:-$HOME/.config/opencode/serve-interactive.env}" "$directory"
      printf '%s\0%s\0%s\0%s\0' opencode-bench.service "${GATE_URL_3040:-http://127.0.0.1:3040}" \
        "${GATE_AUTH_ENV_3040:-$HOME/.config/opencode/serve-bench.env}" "$directory"
    done < "$tmp/dirs"
  } > "$tmp/jobs"
  remaining=$((deadline - $(date +%s)))
  if (( remaining <= 0 )) || ! timeout "$remaining" xargs -0 -r -n 4 -P 8 bash -c 'probe "$@"' _ \
    < "$tmp/jobs" > "$tmp/busy"; then
    printf 'cannot establish idleness: probe failed or budget exhausted\n' >&2
    failed=true
  fi
  if [[ -s "$tmp/busy" ]]; then
    sort "$tmp/busy"
    failed=true
  fi
fi

if [[ "$failed" == true ]]; then
  if [[ "$force" == true ]]; then
    printf 'WARNING: forcing past busy or unknown OpenCode sessions\n' >&2
    exit 0
  fi
  exit 1
fi
