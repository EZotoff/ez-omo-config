#!/bin/bash
set -e
trap 'echo "ERROR: preDelete hook failed at line $LINENO"; exit 1' ERR

PROJECT_ID=$(basename "$(git rev-parse --show-toplevel)")
STATE_DIR="$HOME/.local/share/opencode/worktree-state/$PROJECT_ID"
BRANCH=$(git branch --show-current)
STATE_FILE="$STATE_DIR/worktrees/$BRANCH.json"

if [ -f "$STATE_FILE" ]; then
  CONTAINER_ID=$(jq -r '.dockerContainerId // empty' "$STATE_FILE" 2>/dev/null)
  if [ -n "$CONTAINER_ID" ]; then
    docker stop "$CONTAINER_ID" 2>/dev/null || true
    docker rm "$CONTAINER_ID" 2>/dev/null || true
  fi

  PORT=$(jq -r '.port // empty' "$STATE_FILE" 2>/dev/null)
  if [ -n "$PORT" ] && [ "$PORT" != "null" ]; then
    PORTS_FILE="$STATE_DIR/ports.json"
    if [ -f "$PORTS_FILE" ]; then
      TEMP_FILE=$(mktemp)
      jq --arg port "$PORT" 'del(.[$port])' "$PORTS_FILE" > "$TEMP_FILE" && mv "$TEMP_FILE" "$PORTS_FILE"
    fi
  fi

  TEMP_FILE=$(mktemp)
  jq '.status = "deleted"' "$STATE_FILE" > "$TEMP_FILE" && mv "$TEMP_FILE" "$STATE_FILE"
fi

COMPOSE_FILE="/tmp/worktree-compose-$PROJECT_ID/docker-compose-$BRANCH.yml"
rm -f "$COMPOSE_FILE" 2>/dev/null || true

echo "Worktree cleanup complete: $BRANCH"

# --- Vera Cleanup ---
WORKTREE_REAL_PATH="$(realpath "$(pwd)")"
WORKSPACE_KEY="$(basename "$WORKTREE_REAL_PATH")-$(printf '%s' "$WORKTREE_REAL_PATH" | sha1sum | cut -c1-8)"
WATCHERS_DIR="$HOME/.local/share/opencode/worktree-state/$PROJECT_ID/vera-watchers"
WATCHER_STATE="$WATCHERS_DIR/$WORKSPACE_KEY.json"
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

is_positive_pid() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
  esac
  [ "$1" -gt 1 ] && [ "$1" -le 4194304 ]
}

pid_owned_by_current_user() {
  local pid="$1"
  local proc_uid
  local current_uid

  [ -r "/proc/$pid/status" ] || return 1
  proc_uid=$(awk '/^Uid:/ {print $2; exit}' "/proc/$pid/status" 2>/dev/null || true)
  current_uid=$(id -u)
  [ -n "$proc_uid" ] && [ "$proc_uid" = "$current_uid" ]
}

pid_cmdline_matches_workspace() {
  local pid="$1"
  local cmdline

  [ -r "/proc/$pid/cmdline" ] || return 1
  cmdline=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null || true)
  [ -n "$cmdline" ] || return 1
  case "$cmdline" in
    *vera*watch*"$WORKTREE_REAL_PATH"*) return 0 ;;
    *) return 1 ;;
  esac
}

safe_vera_watcher_pid() {
  local pid="$1"
  is_positive_pid "$pid" || return 1
  kill -0 -- "$pid" 2>/dev/null || return 1
  pid_owned_by_current_user "$pid" || return 1
  pid_cmdline_matches_workspace "$pid" || return 1
}

if [ -f "$WATCHER_STATE" ]; then
  PID=$(jq -r 'if (.pid | type) == "number" then (.pid | tostring) else "" end' "$WATCHER_STATE" 2>/dev/null)
  STATUS=$(jq -r '.status // empty' "$WATCHER_STATE" 2>/dev/null)
  AUTOMATION_MODE=$(jq -r '.automationMode // "manual"' "$WATCHER_STATE" 2>/dev/null)

  if [ -n "$PID" ] && [ "$STATUS" = "running" ] && [ "$AUTOMATION_MODE" = "autostart" ]; then
    if safe_vera_watcher_pid "$PID"; then
      echo "Stopping Vera watcher (PID: $PID) for workspace: $WORKSPACE_KEY"
      kill -- "$PID" 2>/dev/null || true

      # Wait up to 5 seconds for graceful shutdown
      for i in 1 2 3 4 5; do
        if ! kill -0 -- "$PID" 2>/dev/null; then
          break
        fi
        sleep 1
      done

      # Force kill only after re-validating the still-running process.
      if safe_vera_watcher_pid "$PID"; then
        echo "WARN: Vera watcher did not stop gracefully, forcing kill (PID: $PID)"
        kill -9 -- "$PID" 2>/dev/null || true
      fi
    else
      echo "WARN: Refusing to stop unverified Vera watcher PID: $PID"
    fi
  fi

  TEMP_FILE=$(mktemp)
  jq --arg ts "$TIMESTAMP" '.status = "stopped" | .pid = null | .lastVerifiedAt = null | .stoppedAt = $ts' "$WATCHER_STATE" > "$TEMP_FILE" && mv "$TEMP_FILE" "$WATCHER_STATE"
  rm -f "$WATCHER_STATE"
  echo "Vera watcher state removed for workspace: $WORKSPACE_KEY"
else
  echo "INFO: No Vera watcher state found for workspace: $WORKSPACE_KEY"
fi
