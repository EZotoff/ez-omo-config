#!/usr/bin/env bash
set -euo pipefail

source tests/helpers.sh

assert_dir_exists "scripts/wisdom"
assert_file_exists "install.sh"

if [[ ! -x "install.sh" ]]; then
    echo "FAIL: Script is not executable: install.sh"
    TESTS_FAILED=$((TESTS_FAILED + 1))
else
    TESTS_PASSED=$((TESTS_PASSED + 1))
fi

for script in scripts/wisdom/*.sh; do
    assert_file_exists "$script"
    if [[ ! -x "$script" ]]; then
        echo "FAIL: Script is not executable: $script"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    else
        TESTS_PASSED=$((TESTS_PASSED + 1))
    fi
done

if [[ "$TESTS_FAILED" -gt 0 ]]; then
    exit 1
fi

exit 0
