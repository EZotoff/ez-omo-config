#!/usr/bin/env bash

# Test harness — discover and run all test_*.sh scripts
# Usage: bash tests/run_all.sh
#
# Auto-discovery covers the patch gates: test_patch_entries.sh (schema)
# and test_patch_lockfile.sh (bijection/ancestry/remote presence).

set -o errexit

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOTAL_PASSED=0
TOTAL_FAILED=0

# Run regression corpus (aggregate — standard tests still run after a corpus
# failure, but the corpus result is FATAL for the final exit code: plan DoD
# requires exit 0 only WITH regressions passing; review-enforcer consumes it)
CORPUS_RC=0
echo ""
echo "Running regression corpus..."
echo "----------------------------------------"
if bash "$SCRIPT_DIR/run_regressions.sh"; then
    echo "Regression corpus: PASS"
else
    CORPUS_RC=1
    echo "Regression corpus: FAIL (continuing with standard tests; final exit will be non-zero)"
fi
echo ""
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

# Wisdom test scripts (scripts/wisdom/test-*.sh) — run each under a fresh
# temp HOME so they NEVER touch the live wisdom store (~/.sisyphus/wisdom/).
# All store paths resolve from $HOME via knowledge-constants.sh/wisdom-common.sh.
echo "Running wisdom tests..."
echo "----------------------------------------"
for test_script in "$SCRIPT_DIR"/../scripts/wisdom/test-*.sh; do
    # Skip if no matching files (glob returns the pattern itself)
    if [[ ! -f "$test_script" ]]; then
        continue
    fi

    tests_found=$((tests_found + 1))
    test_name=$(basename "$test_script")

    echo "Running: $test_name (isolated temp HOME)"
    wisdom_tmp_home="$(mktemp -d)"
    # Unset store-path overrides so isolation cannot be bypassed via env
    if env -u WISDOM_ROOT -u WISDOM_EVENTS_PATH -u WISDOM_BASE_DIR -u WISDOM_SYSTEM_DIR HOME="$wisdom_tmp_home" bash "$test_script"; then
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

# Exit non-zero if any test failed OR the regression corpus failed
if [[ $TOTAL_FAILED -gt 0 || $CORPUS_RC -ne 0 ]]; then
    exit 1
fi

exit 0
