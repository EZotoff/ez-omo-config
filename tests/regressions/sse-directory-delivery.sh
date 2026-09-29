#!/usr/bin/env bash
# Regression: SSE /event directory-filter removal (opencode--sse-directory-filter-removal).
# Proves the instance /event route no longer drops events for cross-directory
# subscribers (worktrees, external observers).
set -o errexit
source "$(cd "$(dirname "$0")/.." && pwd)/helpers.sh"

SRC="${OPENCODE_SRC:-$HOME/src/opencode}"
FILE="$SRC/packages/opencode/src/server/routes/instance/httpapi/handlers/event.ts"
if [[ ! -f "$FILE" ]]; then echo "SKIP: $FILE not found"; exit 0; fi

# The directory-equality conjunct must be absent from the event stream filter.
if grep -q "directory === instance.directory" "$FILE"; then
  echo "FAIL: instance /event route still filters by directory — external subscribers starve"
  exit 1
fi
assert_grep "workspaceID === undefined" "$FILE"
echo "PASS: /event route delivers cross-directory events"
