#!/usr/bin/env bash

# Skill Nudger runtime harness regression wrapper
# Runs all harness test cases and exits 0 if all pass

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ -f "$SCRIPT_DIR/helpers.sh" ]]; then
    source "$SCRIPT_DIR/helpers.sh"
fi

HARNESS="$SCRIPT_DIR/skill-nudger/harness.mjs"

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

run_case "repeated-failure"
run_case "retryable-error"
run_case "port-binding"
run_case "loop"
run_case "dedup-and-cap"
run_case "cooldown"
run_case "agent-scoping"
run_case "stale-drop"
run_case "no-false-positives"
run_case "session-cleanup"
run_case "circuit-breaker"
run_case "disabled-signal"

echo ""
echo "skill-nudger harness: Pass: $TOTAL_PASSED | Fail: $TOTAL_FAILED"

if [[ $TOTAL_FAILED -gt 0 ]]; then
    exit 1
fi
exit 0
