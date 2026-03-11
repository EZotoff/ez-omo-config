#!/usr/bin/env bash

# Test helpers — common assertions and counters for test harness
# Usage: source tests/helpers.sh in test scripts

# Global counters
TESTS_PASSED=0
TESTS_FAILED=0

# assert_file_exists — verify file exists
assert_file_exists() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        echo "FAIL: File does not exist: $file"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
    TESTS_PASSED=$((TESTS_PASSED + 1))
    return 0
}

# assert_dir_exists — verify directory exists
assert_dir_exists() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        echo "FAIL: Directory does not exist: $dir"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
    TESTS_PASSED=$((TESTS_PASSED + 1))
    return 0
}

# assert_grep — verify pattern found in file
assert_grep() {
    local pattern="$1"
    local file="$2"
    if ! grep -q "$pattern" "$file"; then
        echo "FAIL: Pattern not found in $file: $pattern"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
    TESTS_PASSED=$((TESTS_PASSED + 1))
    return 0
}

# assert_no_grep — verify pattern NOT found in file
assert_no_grep() {
    local pattern="$1"
    local file="$2"
    if grep -q "$pattern" "$file"; then
        echo "FAIL: Pattern unexpectedly found in $file: $pattern"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
    TESTS_PASSED=$((TESTS_PASSED + 1))
    return 0
}
