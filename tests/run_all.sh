#!/usr/bin/env bash

# Test harness — discover and run all test_*.sh scripts
# Usage: bash tests/run_all.sh

set -o errexit

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOTAL_PASSED=0
TOTAL_FAILED=0

# Auto-discover test scripts
tests_found=0
for test_script in "$SCRIPT_DIR"/test_*.sh; do
    # Skip if no matching files (glob returns the pattern itself)
    if [[ ! -f "$test_script" ]]; then
        continue
    fi
    
    tests_found=$((tests_found + 1))
    test_name=$(basename "$test_script")
    
    echo "Running: $test_name"
    if bash "$test_script"; then
        TOTAL_PASSED=$((TOTAL_PASSED + 1))
    else
        TOTAL_FAILED=$((TOTAL_FAILED + 1))
    fi
    echo ""
done

# Print summary
echo "=========================================="
if [[ $tests_found -eq 0 ]]; then
    echo "No test scripts found (test_*.sh)"
    echo "Pass: 0 | Fail: 0"
else
    echo "Test Summary"
    echo "Pass: $TOTAL_PASSED | Fail: $TOTAL_FAILED"
fi
echo "=========================================="

# Exit non-zero if any test failed
if [[ $TOTAL_FAILED -gt 0 ]]; then
    exit 1
fi

exit 0
