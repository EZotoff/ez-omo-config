#!/usr/bin/env bash

# Provider-connect-retry near-empty detection harness wrapper
# Runs all H1-H6 scenarios and exits 0 if all pass.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ -f "$SCRIPT_DIR/helpers.sh" ]]; then
    source "$SCRIPT_DIR/helpers.sh"
fi

HARNESS="$SCRIPT_DIR/provider-connect-retry-min-output/harness.mjs"

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

run_case "H1-zero-token-root"
run_case "H2-child-near-empty"
run_case "H3-child-above-threshold"
run_case "H4-root-near-empty-no-dispatch"
run_case "H5-min-tokens-zero-disabled"
run_case "H6-child-at-threshold"

echo ""
echo "=========================================="
echo "Provider-connect-retry min-output: $TOTAL_PASSED passed, $TOTAL_FAILED failed"
echo "=========================================="

if [[ $TOTAL_FAILED -gt 0 ]]; then
    exit 1
fi

exit 0
