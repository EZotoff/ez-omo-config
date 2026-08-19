#!/usr/bin/env bash

# Provider-connect-retry runtime harness regression wrapper
# Runs all harness test cases and exits 0 if all pass

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ -f "$SCRIPT_DIR/helpers.sh" ]]; then
    source "$SCRIPT_DIR/helpers.sh"
fi

HARNESS="$SCRIPT_DIR/provider-connect-retry/harness.mjs"

TOTAL_PASSED=0
TOTAL_FAILED=0

run_case() {
    local case_name="$1"
    echo "Running: $case_name"
    if node "$HARNESS" --case "$case_name"; then
        TOTAL_PASSED=$((TOTAL_PASSED + 1))
    else
        TOTAL_FAILED=$((TOTAL_FAILED + 1))
        echo "FAIL: $case_name"
    fi
}

run_case "compaction-dispatch"
run_case "chain-advance-exhaustion"
run_case "dual-event-dedup"
run_case "chat-failure-unchanged"
run_case "child-session-gate"
run_case "success-resets-chain"
run_case "user-message-resets-chain"
run_case "export-surface"

echo ""
echo "provider-connect-retry harness: Pass: $TOTAL_PASSED | Fail: $TOTAL_FAILED"

if [[ $TOTAL_FAILED -gt 0 ]]; then
    exit 1
fi
exit 0
