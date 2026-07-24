#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../helpers.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCRIPT="$(cd "$(dirname "$0")/../.." && pwd)/scripts/verify-live-patches.sh"

if [[ ! -f "$SCRIPT" ]]; then
    echo "FAIL: verify-live-patches.sh not found"
    exit 1
fi

if [[ -f "$REPO_ROOT/plugins/live-patch-guard.ts" ]]; then
    echo "FAIL: plugins/live-patch-guard.ts exists"
    exit 1
fi
TESTS_PASSED=$((TESTS_PASSED + 1))
exit 0
