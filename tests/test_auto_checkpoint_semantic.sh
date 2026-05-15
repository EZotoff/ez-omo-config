#!/usr/bin/env bash

# Auto-checkpoint semantic harness regression wrapper
# Runs all harness test cases and exits 0 if all pass

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ -f "$SCRIPT_DIR/helpers.sh" ]]; then
    source "$SCRIPT_DIR/helpers.sh"
fi

HARNESS="$SCRIPT_DIR/auto-checkpoint/harness.mjs"

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

run_case "helper-sessions-ignored"
run_case "child-activity-rolls-up-to-root"
run_case "predirty-path-skipped"
run_case "conflicting-root-ownership-skips"
run_case "root-owned-file-remains-eligible"
run_case "rename-delete-untracked-collected"
run_case "binary-candidate-skips"
run_case "diff-budget-overflow-skips"
run_case "structured-helper-response-accepted"
run_case "malformed-llm-response-skips"
run_case "llm-out-of-scope-file-skips"
run_case "staged-foreign-index-preserved"
run_case "exact-validated-subset-committed"
run_case "delete-and-rename-commit-via-temp-index"
run_case "disjoint-root-commits"
run_case "skip-does-not-advance-head"
run_case "git-operation-in-progress-skips"

echo ""
echo "=========================================="
echo "Auto-checkpoint semantic: $TOTAL_PASSED passed, $TOTAL_FAILED failed"
echo "=========================================="

if [[ $TOTAL_FAILED -gt 0 ]]; then
    exit 1
fi

exit 0
