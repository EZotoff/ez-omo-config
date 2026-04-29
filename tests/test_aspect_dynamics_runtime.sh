#!/usr/bin/env bash

# Aspect Dynamics runtime harness regression wrapper
# Runs all harness test cases and exits 0 if all pass

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ -f "$SCRIPT_DIR/helpers.sh" ]]; then
    source "$SCRIPT_DIR/helpers.sh"
fi

HARNESS="$SCRIPT_DIR/aspect-dynamics/harness.mjs"

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

run_case "registration-ok"
run_case "child-session-ignored"
run_case "dedup-same-assistant"
run_case "circuit-breaker"
run_case "context-window-respected"
run_case "prefilter-skip"
run_case "prefilter-hit"
run_case "reserved-fields-idle"
run_case "no-network-calls"
run_case "below-threshold"
run_case "threshold-crossed"
run_case "tie-break"
run_case "recursive-nudge"
run_case "disabled"
run_case "invalid-config"

echo ""
echo "=========================================="
echo "Aspect Dynamics runtime: $TOTAL_PASSED passed, $TOTAL_FAILED failed"
echo "=========================================="

if [[ $TOTAL_FAILED -gt 0 ]]; then
    exit 1
fi

exit 0
