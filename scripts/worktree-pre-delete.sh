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

# =============================================================================
# Vera Cleanup — stop semantic code search watcher
# =============================================================================

WORKSPACE_KEY="$(basename "$(pwd)")-$(echo -n "$(realpath "$(pwd)")" | sha1sum | cut -c1-8)"
WATCHERS_DIR="$HOME/.local/share/opencode/worktree-state/$PROJECT_ID/vera-watchers"
VERA_STATE_FILE="$WATCHERS_DIR/$WORKSPACE_KEY.json"

if [ -f "$VERA_STATE_FILE" ]; then
  VERA_PID=$(jq -r '.pid // empty' "$VERA_STATE_FILE" 2>/dev/null)
  VERA_STATUS=$(jq -r '.status // empty' "$VERA_STATE_FILE" 2>/dev/null)

  if [ -n "$VERA_PID" ] && [ "$VERA_PID" != "null" ] && [ "$VERA_STATUS" = "running" ]; then
    kill "$VERA_PID" 2>/dev/null || true

    WAITED=0
    while [ "$WAITED" -lt 5 ]; do
      if ! kill -0 "$VERA_PID" 2>/dev/null; then
        break
      fi
      sleep 1
      WAITED=$((WAITED + 1))
    done

    if kill -0 "$VERA_PID" 2>/dev/null; then
      kill -9 "$VERA_PID" 2>/dev/null || true
    fi
  fi

  STOPPED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  TEMP_FILE=$(mktemp)
  jq --arg stoppedAt "$STOPPED_AT" \
     '.status = "stopped" | .pid = null | .lastVerifiedAt = $stoppedAt' \
     "$VERA_STATE_FILE" > "$TEMP_FILE" && mv "$TEMP_FILE" "$VERA_STATE_FILE"
fi

echo "Vera watcher cleanup complete for workspace $WORKSPACE_KEY"
