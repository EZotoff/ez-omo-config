#!/usr/bin/env bash

# Worktree reclaim harness regression wrapper
# Verifies the worktree_delete target contract: resolution, merged-delete,
# unmerged-keep, dirty-salvage, and no-empty-snapshot (leak prevention).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ -f "$SCRIPT_DIR/helpers.sh" ]]; then
    source "$SCRIPT_DIR/helpers.sh"
fi

if ! command -v bun >/dev/null 2>&1; then
    echo "SKIP: bun not available"
    exit 0
fi

HARNESS="$SCRIPT_DIR/worktree-reclaim/harness.mjs"

if [[ ! -f "$HARNESS" ]]; then
    echo "FAIL: harness missing: $HARNESS"
    exit 1
fi

if bun "$HARNESS"; then
    echo "worktree-reclaim: PASS"
    exit 0
else
    echo "worktree-reclaim: FAIL"
    exit 1
fi
