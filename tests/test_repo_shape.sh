#!/usr/bin/env bash

# Test repository shape — verify expected directories and files exist
# Usage: bash tests/test_repo_shape.sh

# Source helpers for assertions
source tests/helpers.sh

# Test for expected directories
assert_dir_exists "commands/"
assert_dir_exists "configs/"
assert_dir_exists "plugins/"
assert_dir_exists "skills/"
assert_dir_exists "scripts/"
assert_dir_exists "extras/"
assert_dir_exists "docs/"
assert_dir_exists "tests/"

# Test for expected files
assert_file_exists "MANIFEST.md"
assert_file_exists "LICENSE"
assert_file_exists "commands/models-preset.md"

# Report results
echo ""
echo "Tests passed: $TESTS_PASSED"
echo "Tests failed: $TESTS_FAILED"
echo ""

if [[ $TESTS_FAILED -gt 0 ]]; then
    exit 1
else
    exit 0
fi
