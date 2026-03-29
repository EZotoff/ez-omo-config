#!/bin/bash
set -e
trap 'echo "ERROR: postCreate hook failed at line $LINENO"; exit 1' ERR

PROJECT_ID=$(basename "$(git rev-parse --show-toplevel)")
STATE_DIR="$HOME/.local/share/opencode/worktree-state/$PROJECT_ID"
WORKTREES_DIR="$STATE_DIR/worktrees"
BRANCH=$(git branch --show-current)
WORKTREE_PATH=$(pwd)

mkdir -p "$WORKTREES_DIR"

ACTIVE_COUNT=$(find "$WORKTREES_DIR" -name "*.json" -exec grep -l '"status": *"active"' {} \; 2>/dev/null | wc -l)
if [ "$ACTIVE_COUNT" -ge 4 ]; then
  echo "ERROR: Maximum parallel worktrees (4) reached"
  exit 1
fi

DEPLOYMENT_PORTS="$HOME/.sisyphus/ports.json"
if [ ! -f "$DEPLOYMENT_PORTS" ]; then
  echo "WARN: No deployment port registry found at $DEPLOYMENT_PORTS"
  echo "Port allocation skipped. Run /deploy to reserve a port range for project '$PROJECT_ID'"
  PORT="null"
else
  RANGE_START=$(jq -r ".ranges[\"$PROJECT_ID\"].start // empty" "$DEPLOYMENT_PORTS")
  RANGE_END=$(jq -r ".ranges[\"$PROJECT_ID\"].end // empty" "$DEPLOYMENT_PORTS")

  if [ -z "$RANGE_START" ] || [ -z "$RANGE_END" ]; then
    echo "WARN: No port range reserved for project '$PROJECT_ID'"
    echo "Port allocation skipped. Run /deploy to reserve a port range"
    PORT="null"
  else
    PORTS_FILE="$STATE_DIR/ports.json"
    [ ! -f "$PORTS_FILE" ] && echo "{}" > "$PORTS_FILE"

    PORT=""
    for P in $(seq "$RANGE_START" "$RANGE_END"); do
      if ! jq -e ".[\"$P\"]" "$PORTS_FILE" > /dev/null 2>&1; then
        PORT=$P
        break
      fi
    done

    if [ -z "$PORT" ]; then
      echo "WARN: No available ports in project range $RANGE_START-$RANGE_END"
      PORT="null"
    else
      TEMP_FILE=$(mktemp)
      jq --arg port "$PORT" --arg branch "$BRANCH" '.[$port] = $branch' "$PORTS_FILE" > "$TEMP_FILE" && mv "$TEMP_FILE" "$PORTS_FILE"
    fi
  fi
fi

CREATED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
TIMEOUT_AT=$(date -u -d '+30 minutes' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v+30M +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)

STATE_FILE="$WORKTREES_DIR/$BRANCH.json"
cat > "$STATE_FILE" << EOF
{
  "branch": "$BRANCH",
  "worktreePath": "$WORKTREE_PATH",
  "status": "active",
  "port": $PORT,
  "dockerContainerId": "",
  "createdAt": "$CREATED_AT",
  "agentSessionId": "",
  "timeoutAt": "$TIMEOUT_AT"
}
EOF

if command -v docker &> /dev/null && [ -f "Dockerfile" ] && [ -f ".opencode/docker/worktree-compose.template.yml" ]; then
  COMPOSE_DIR="/tmp/worktree-compose-$PROJECT_ID"
  mkdir -p "$COMPOSE_DIR"
  COMPOSE_FILE="$COMPOSE_DIR/docker-compose-$BRANCH.yml"
  sed -e "s|\${WORKTREE_PATH}|$WORKTREE_PATH|g" \
      -e "s|\${HOST_PORT}|$PORT|g" \
      -e "s|\${BRANCH_NAME}|$BRANCH|g" \
      ".opencode/docker/worktree-compose.template.yml" > "$COMPOSE_FILE"
  docker compose -f "$COMPOSE_FILE" up -d
  CONTAINER_ID=$(docker compose -f "$COMPOSE_FILE" ps -q 2>/dev/null | head -1)
  if [ -n "$CONTAINER_ID" ]; then
    TEMP_FILE=$(mktemp)
    jq --arg cid "$CONTAINER_ID" '.dockerContainerId = $cid' "$STATE_FILE" > "$TEMP_FILE" && mv "$TEMP_FILE" "$STATE_FILE"
  fi
fi

echo "Worktree state created: $STATE_FILE"
echo "Port allocated: $PORT"
