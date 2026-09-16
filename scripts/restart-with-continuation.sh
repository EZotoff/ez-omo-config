#!/usr/bin/env bash
# restart-with-continuation.sh — snapshot active top-level OpenCode sessions,
# restart opencode.service, then inject a "continue" prompt into each.
#
# Usage:
#   restart-with-continuation.sh                 # dry-run: snapshot only, no restart, no resume
#   restart-with-continuation.sh --restart       # snapshot -> systemctl --user restart -> resume
#   restart-with-continuation.sh --restart --prompt "Pick up where you left off."
#   restart-with-continuation.sh --resume-only --state-file <file.json>   # re-inject from a saved snapshot
#
# Env (defaults auto-detected):
#   OPENCODE_URL      base URL of the serve instance (default http://127.0.0.1:3021)
#   OPENCODE_SERVER_PASSWORD   server Basic-auth password (auto-read from openchamber.env)
#   OPENCODE_SERVER_USERNAME   server Basic-auth username (default: opencode)
#
# Evidence states: snapshot = live API read; resume = POST /session/:id/prompt_async
# (fire-and-forget; the target session runs the prompt on next available turn).

set -euo pipefail

STATE_DIR="${XDG_STATE_DIR:-$HOME/.local/share/opencode}/restart-continuations"
DEFAULT_PROMPT="The OpenCode server was restarted for maintenance and your previous turn was interrupted. Continue exactly where you left off."

RESTART=false
RESUME_ONLY=false
PROMPT="$DEFAULT_PROMPT"
STATE_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --restart) RESTART=true ;;
    --resume-only) RESUME_ONLY=true ;;
    --prompt) PROMPT="$2"; shift ;;
    --state-file) STATE_FILE="$2"; shift ;;
    --url) OPENCODE_URL="$2"; shift ;;
    --password) CLI_PASSWORD="$2"; shift ;;
    --username) OPENCODE_SERVER_USERNAME="$2"; shift ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

OPENCODE_URL="${OPENCODE_URL:-http://127.0.0.1:3021}"
OPENCODE_SERVER_USERNAME="${OPENCODE_SERVER_USERNAME:-opencode}"
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
  local sessions out dirs tmpstatus tmpsessions
  sessions="$(api GET "/session?limit=200")"
  # /session/status is instance-scoped: query it once per distinct session directory.
  dirs="$(printf '%s' "$sessions" | python3 -c 'import json,sys; print("\n".join(sorted({s.get("directory","") for s in json.load(sys.stdin)})))')"
  mkdir -p "$STATE_DIR"
  out="${STATE_FILE:-$STATE_DIR/snapshot-$(date +%Y%m%d-%H%M%S).json}"
  tmpstatus="$(mktemp)" tmpsessions="$(mktemp)"
  printf '%s' "$sessions" > "$tmpsessions"
  : > "$tmpstatus"
  local d
  while IFS= read -r d; do
    [[ -n "$d" ]] || continue
    local st
    st="$(api GET "/session/status?directory=$(python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1], safe=''))" "$d")" || true)"
    [[ -n "$st" ]] && printf '%s' "$st" >> "$tmpstatus" && echo >> "$tmpstatus"
  done <<< "$dirs"
  STATUS_FILE="$tmpstatus" SESSIONS_FILE="$tmpsessions" OUT="$out" python3 - <<'PYEOF'
import json, os, time
merged = {}
for line in open(os.environ["STATUS_FILE"]):
    line = line.strip()
    if not line:
        continue
    merged.update(json.loads(line))
status = merged
sessions = json.load(open(os.environ["SESSIONS_FILE"]))
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
  local deadline=$((SECONDS + 90))
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
    body = json.dumps({"parts": [{"type": "text", "text": os.environ["PROMPT"]}]})
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

# --- Main ------------------------------------------------------------------
if [[ "$RESUME_ONLY" == true ]]; then
  [[ -n "$STATE_FILE" && -r "$STATE_FILE" ]] || { echo "--resume-only needs --state-file" >&2; exit 2; }
  resume "$STATE_FILE"
  exit $?
fi

snapshot

if [[ "$RESTART" != true ]]; then
  log "dry-run: snapshot saved. Re-run with --restart to restart and resume."
  exit 0
fi

log "restarting opencode.service"
systemctl --user restart opencode.service
wait_ready
resume "$(ls -t "$STATE_DIR"/snapshot-*.json 2>/dev/null | head -1 || echo "$STATE_FILE")"
