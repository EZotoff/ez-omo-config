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
