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

# assert_command_fails — verify command exits non-zero
assert_command_fails() {
    local description="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        echo "FAIL: Command expected to fail but succeeded: $description"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
    TESTS_PASSED=$((TESTS_PASSED + 1))
    return 0
}

# assert_json_contains_plugin — verify JSON file plugin array contains value
assert_json_contains_plugin() {
    local json_file="$1"
    local plugin_name="$2"
    if ! python3 -c "
import json, sys
try:
    with open('$json_file') as f:
        data = json.load(f)
    plugins = data.get('plugin', [])
    if any('$plugin_name' in str(p) for p in plugins):
        sys.exit(0)
    else:
        sys.exit(1)
except Exception as e:
    print(f'JSON parse error: {e}')
    sys.exit(1)
" 2>/dev/null; then
        echo "FAIL: Plugin '$plugin_name' not found in $json_file plugin array"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
    TESTS_PASSED=$((TESTS_PASSED + 1))
    return 0
}
