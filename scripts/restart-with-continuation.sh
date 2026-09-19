#!/usr/bin/env bash
# restart-with-continuation.sh — snapshot active top-level OpenCode sessions,
# restart opencode.service, then inject a "continue" prompt into each.
#
# ALSO the engine behind the systemd continuation hooks (see the continuation.conf
# drop-ins): ExecStop= snapshots busy sessions on EVERY stop/restart of the
# managed units and ExecStartPost= resumes them — so plain `systemctl restart` continues sessions by default.
#
# Usage:
#   restart-with-continuation.sh                 # dry-run: snapshot only, no restart, no resume
#   restart-with-continuation.sh --restart       # snapshot -> systemctl --user restart -> resume
#   restart-with-continuation.sh --restart --prompt "Pick up where you left off."
#   restart-with-continuation.sh --bare-restart  # restart WITHOUT continuation (explicit opt-out)
#   restart-with-continuation.sh --resume-only --state-file <file.json>   # re-inject from a saved snapshot
#   restart-with-continuation.sh hook-snapshot <unit> <url> <auth-env-file>   # ExecStop hook
#   restart-with-continuation.sh hook-resume <unit> <url> <auth-env-file>     # ExecStartPost hook
#
# Env (defaults auto-detected):
#   OPENCODE_URL      base URL of the serve instance (default http://127.0.0.1:3021)
#   OPENCODE_SERVER_PASSWORD   server Basic-auth password (auto-read from serve.env)
#   OPENCODE_SERVER_USERNAME   server Basic-auth username (default: opencode)
#
# Evidence states: snapshot = live API read; resume = POST /session/:id/prompt_async
# (fire-and-forget; the target session runs the prompt on next available turn).

set -euo pipefail

STATE_DIR="${XDG_STATE_DIR:-$HOME/.local/share/opencode}/restart-continuations"
DEFAULT_PROMPT="The OpenCode server was restarted for maintenance and your previous turn was interrupted. Continue exactly where you left off."

SERVICE_UNIT="${SERVICE_UNIT:-opencode.service}"
MAX_AGE_SECONDS="${MAX_AGE_SECONDS:-86400}"
RESUME_TTL_SECONDS="${RESUME_TTL_SECONDS:-3600}"
RESTART=false
BARE_RESTART=false
RESUME_ONLY=false
HOOK_MODE=""
PROMPT="$DEFAULT_PROMPT"
STATE_FILE=""

case "${1:-}" in
  hook-snapshot|hook-resume) HOOK_MODE="$1" ;;
esac

log() { printf '[restart-continuation] %s\n' "$*"; }

if [[ -n "$HOOK_MODE" ]];
  then
  SERVICE_UNIT="${2:-}"; OPENCODE_URL="${3:-}"; AUTH_ENV="${4:-}"
else
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --restart) RESTART=true ;;
      --bare-restart) BARE_RESTART=true; RESTART=true ;;
      --resume-only) RESUME_ONLY=true ;;
      --prompt) PROMPT="$2"; shift ;;
      --state-file) STATE_FILE="$2"; shift ;;
      --url) OPENCODE_URL="$2"; shift ;;
      --service) SERVICE_UNIT="$2"; shift ;;
      --password) CLI_PASSWORD="$2"; shift ;;
      --username) OPENCODE_SERVER_USERNAME="$2"; shift ;;
      -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
      *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
    shift
  done
fi

OPENCODE_SERVER_USERNAME="${OPENCODE_SERVER_USERNAME:-opencode}"
if [[ -n "$HOOK_MODE" ]]; then
  if [[ -n "$AUTH_ENV" && -r "$AUTH_ENV" ]]; then
    OPENCODE_SERVER_PASSWORD="$(grep '^OPENCODE_SERVER_PASSWORD=' "$AUTH_ENV" | cut -d= -f2-)"
  fi
  if [[ -z "${OPENCODE_SERVER_PASSWORD:-}" ]]; then
    log "no password via $AUTH_ENV; hook no-op"
    exit 0
  fi
else
  OPENCODE_URL="${OPENCODE_URL:-http://127.0.0.1:3021}"
  ENV_FILE="$HOME/.config/opencode/serve.env"
  if [[ -n "${CLI_PASSWORD:-}" ]]; then
    OPENCODE_SERVER_PASSWORD="$CLI_PASSWORD"
  elif [[ -r "$ENV_FILE" ]] && grep -q '^OPENCODE_SERVER_PASSWORD=' "$ENV_FILE"; then
    # The service's own env file is authoritative for the systemd-managed server;
    # an inherited OPENCODE_SERVER_PASSWORD may belong to a different instance.
    OPENCODE_SERVER_PASSWORD="$(grep '^OPENCODE_SERVER_PASSWORD=' "$ENV_FILE" | cut -d= -f2-)"
  fi
  if [[ -z "${OPENCODE_SERVER_PASSWORD:-}" ]]; then
    echo "ERROR: no password: use --password, $ENV_FILE, or OPENCODE_SERVER_PASSWORD" >&2
    exit 1
  fi
fi
api() { # api <method> <path> [json-body]
  local method="$1" path="$2" body="${3:-}"
  if [[ -n "$body" ]]; then
    curl -sS -f -u "$OPENCODE_SERVER_USERNAME:$OPENCODE_SERVER_PASSWORD" \
      -X "$method" -H 'Content-Type: application/json' -d "$body" \
      "$OPENCODE_URL$path"
  else
    curl -sS -f -u "$OPENCODE_SERVER_USERNAME:$OPENCODE_SERVER_PASSWORD" \
      -X "$method" "$OPENCODE_URL$path"
  fi
}

log() { printf '[restart-continuation] %s\n' "$*"; }

# --- Snapshot -------------------------------------------------------------
snapshot() {
  local out dirs d tmpstatus tmpdir
  # /session and /session/status are INSTANCE-SCOPED on the HTTP API: the global list
  # only covers the server's root directory, so directory discovery comes straight from
  # the shared session DB (read-only). Only RECENTLY updated dirs are queried — a
  # busy/retry session is by definition recently updated, and sweeping stale bench/tmp
  # dirs is slow enough to race the very turns being snapshotted (2026-09-16 failure).
  dirs="$(MAX_AGE="$MAX_AGE_SECONDS" python3 - <<'PYEOF'
import os, sqlite3, time
db = os.path.expanduser("~/.local/share/opencode/opencode.db")
con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
cutoff = (time.time() - float(os.environ["MAX_AGE"])) * 1000
rows = con.execute(
    "select distinct directory from session "
    "where time_updated >= ? and time_archived is null and directory != ''", (cutoff,))
print("\n".join(sorted(r[0] for r in rows)))
PYEOF
)"
  [[ -n "$dirs" ]] || { echo "ERROR: no recently-active session directories found in DB" >&2; return 1; }
  mkdir -p "$STATE_DIR"
  out="${STATE_FILE:-$STATE_DIR/snapshot-$(date +%Y%m%d-%H%M%S).json}"
  tmpstatus="$(mktemp)" tmpdir="$(mktemp -d)"
  : > "$tmpstatus"
  local i=0 st
  while IFS= read -r d; do
    [[ -n "$d" ]] || continue
    i=$((i + 1))
    local enc="$d"
    enc="$(python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1], safe=''))" "$d")"
    st="$(api GET "/session/status?directory=$enc" || true)"
    [[ -n "$st" ]] && printf '%s\n' "$st" >> "$tmpstatus"
    api GET "/session?directory=$enc&limit=100" > "$tmpdir/sessions-$i.json" 2>/dev/null || true
  done <<< "$dirs"
  STATUS_FILE="$tmpstatus" SESSIONS_DIR="$tmpdir" OUT="$out" python3 - <<'PYEOF'
import glob, json, os, time
merged = {}
for line in open(os.environ["STATUS_FILE"]):
    line = line.strip()
    if line:
        merged.update(json.loads(line))
status = merged
sessions = []
for f in glob.glob(os.path.join(os.environ["SESSIONS_DIR"], "sessions-*.json")):
    try:
        data = json.load(open(f))
        sessions.extend(data if isinstance(data, list) else [])
    except (ValueError, OSError):
        pass
active_types = {"busy", "retry"}
busy_ids = {sid for sid, st in status.items() if st.get("type") in active_types}
by_id = {s["id"]: s for s in sessions}
top_level = []
for sid in busy_ids:
    s = by_id.get(sid)
    if s is None:
        continue
    if s.get("parentID"):          # skip subagent/child sessions
        continue
    if s.get("time", {}).get("archived"):
        continue
    top_level.append({
        "id": sid,
        "title": s.get("title"),
        "directory": s.get("directory"),
        "status": status[sid].get("type"),
        "time_updated": s.get("time", {}).get("updated"),
        "captured_at_ms": int(time.time() * 1000),
        "resume_prompt_target": os.environ.get("OPENCODE_URL", ""),
    })
snapshot = {"prompt_note": "inject via POST /session/<id>/prompt_async", "sessions": top_level}
with open(os.environ["OUT"], "w") as f:
    json.dump(snapshot, f, indent=1)
print(f"{len(top_level)} active top-level session(s) captured -> {os.environ['OUT']}")
for s in top_level:
    print(f"  - {s['id']}  [{s['status']}]  {s['title']}")
PYEOF
  log "$out"
}

# --- Wait for server readiness --------------------------------------------
wait_ready() {
  local timeout="${1:-90}"
  local deadline=$((SECONDS + timeout))
  while (( SECONDS < deadline )); do
    if api GET /session/status >/dev/null 2>&1; then
      log "server is up"
      return 0
    fi
    sleep 2
  done
  echo "ERROR: server did not become ready within 90s" >&2
  return 1
}

# --- Resume ----------------------------------------------------------------
resume() {
  local file="$1"
  SESSIONS_FILE="$file" PROMPT="$PROMPT" OPENCODE_URL="$OPENCODE_URL" \
    OPENCODE_SERVER_USERNAME="$OPENCODE_SERVER_USERNAME" OPENCODE_SERVER_PASSWORD="$OPENCODE_SERVER_PASSWORD" python3 - <<'PYEOF'
import json, os, subprocess, sys
snap = json.load(open(os.environ["SESSIONS_FILE"]))
base = os.environ["OPENCODE_URL"]
auth = [os.environ["OPENCODE_SERVER_USERNAME"], os.environ["OPENCODE_SERVER_PASSWORD"]]
ok = fail = 0
for s in snap.get("sessions", []):
    # synthetic:true marks the part machine-injected (OC Beacon suppresses the
    # "response ready" push for such turns; matches OMO plugin injection shape).
    body = json.dumps({"parts": [{"type": "text", "text": os.environ["PROMPT"], "synthetic": True}]})
    q = ""
    if s.get("directory"):
        from urllib.parse import quote
        q = "?directory=" + quote(s["directory"], safe="")
    r = subprocess.run(
        ["curl", "-sS", "-f", "-u", f"{auth[0]}:{auth[1]}", "-X", "POST",
         "-H", "Content-Type: application/json", "-d", body,
         f"{base}/session/{s['id']}/prompt_async{q}"],
        capture_output=True, text=True)
    if r.returncode == 0:
        print(f"resumed {s['id']}  ({s.get('title')})")
        ok += 1
    else:
        print(f"FAILED {s['id']}: {r.stderr.strip()}", file=sys.stderr)
        fail += 1
print(f"resumed={ok} failed={fail}")
sys.exit(1 if fail else 0)
PYEOF
}

# --- Bypass flag (keeps systemd hooks out of script-driven restarts) --------
bypass_flag() { echo "$STATE_DIR/.bypass-$SERVICE_UNIT"; }
set_bypass() { mkdir -p "$STATE_DIR"; touch "$(bypass_flag)"; }
clear_bypass() { rm -f "$(bypass_flag)"; }
# Returns 0 when hooks should SKIP (flag present and fresh); consumes stale flags.
mtime_of() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || date +%s; }
bypass_active() {
  local f; f="$(bypass_flag)"
  [[ -e "$f" ]] || return 1
  age=$(( $(date +%s) - $(mtime_of "$f") ))
  if (( age > 600 )); then clear_bypass; log "stale bypass flag (${age}s) ignored"; return 1; fi
  return 0
}

# --- Hook modes (invoked by systemd ExecStop / ExecStartPost) ---------------
HOOKS_LOG="$STATE_DIR/hooks.log"
hook_log() { mkdir -p "$STATE_DIR"; printf '%s [hook:%s] %s\n' "$(date +%H:%M:%S)" "$HOOK_MODE" "$*" >> "$HOOKS_LOG"; }

if [[ -n "$HOOK_MODE" ]]; then
  # Hooks must NEVER block or fail the unit operation.
  trap 'exit 0' EXIT
  if [[ "$HOOK_MODE" == hook-snapshot ]]; then
    if bypass_active; then hook_log "bypass flag set for $SERVICE_UNIT; snapshot skipped"; exit 0; fi
    if ! api GET /session/status >/dev/null 2>&1; then
      hook_log "server $OPENCODE_URL unreachable at stop; nothing to snapshot"
      exit 0
    fi
    STATE_FILE="$STATE_DIR/snapshot-$SERVICE_UNIT-$(date +%Y%m%d-%H%M%S).json" snapshot || hook_log "snapshot failed (non-fatal)"
    hook_log "snapshot done for $SERVICE_UNIT"
    exit 0
  fi
  # hook-resume
  if bypass_active; then clear_bypass; hook_log "bypass flag set for $SERVICE_UNIT; resume skipped, flag cleared"; exit 0; fi
latest="$(ls -t "$STATE_DIR"/snapshot-$SERVICE_UNIT-*.json 2>/dev/null | head -1 || true)"
  if [[ -z "$latest" ]]; then hook_log "no snapshot for $SERVICE_UNIT; nothing to resume"; exit 0; fi
  age=$(( $(date +%s) - $(mtime_of "$latest") ))
  if (( age > RESUME_TTL_SECONDS )); then
    hook_log "snapshot ${age}s old (> ${RESUME_TTL_SECONDS}s TTL); resume skipped"
    mv "$latest" "$STATE_DIR/consumed-$(basename "$latest")"
    exit 0
  fi
  SECONDS=0
  wait_ready 45 || { hook_log "server not ready in time; resume skipped"; exit 0; }
  hook_log "resuming from $(basename "$latest")"
  resume "$latest" >> "$HOOKS_LOG" 2>&1 || true
  mv "$latest" "$STATE_DIR/consumed-$(basename "$latest")" 2>/dev/null || true
  exit 0
fi

# --- Main (standalone) ------------------------------------------------------
if [[ "$RESUME_ONLY" == true ]]; then
  [[ -n "$STATE_FILE" && -r "$STATE_FILE" ]] || { echo "--resume-only needs --state-file" >&2; exit 2; }
  resume "$STATE_FILE"
  exit $?
fi

if [[ "$BARE_RESTART" == true ]]; then
  # Explicit opt-out: no snapshot, no resume. The bypass flag keeps the systemd
  # hooks (ExecStop/ExecStartPost) out of this restart.
  log "bare restart of $SERVICE_UNIT (continuation bypassed by request)"
  set_bypass
  trap clear_bypass EXIT
  systemctl --user restart "$SERVICE_UNIT"
  clear_bypass
  trap - EXIT
  exit 0
fi

snapshot

if [[ "$RESTART" != true ]]; then
  log "dry-run: snapshot saved. Re-run with --restart to restart and resume."
  exit 0
fi

# Script-driven restart: bypass the hooks (they would double-resume); this path
# snapshots above and resumes below itself.
log "restarting $SERVICE_UNIT"
set_bypass
trap clear_bypass EXIT
systemctl --user restart "$SERVICE_UNIT"
wait_ready
resume "$(ls -t "$STATE_DIR"/snapshot-*.json 2>/dev/null | head -1 || echo "$STATE_FILE")"
clear_bypass
trap - EXIT
