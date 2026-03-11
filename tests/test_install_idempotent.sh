#!/usr/bin/env bash
set -euo pipefail

source tests/helpers.sh

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_HOME="$(mktemp -d)"
FIRST_OUTPUT="$(mktemp)"
SECOND_OUTPUT="$(mktemp)"

cleanup() {
    rm -rf "$TEST_HOME" "$FIRST_OUTPUT" "$SECOND_OUTPUT"
}
trap cleanup EXIT

HOME="$TEST_HOME" bash "$REPO_ROOT/install.sh" --plugins --skills >"$FIRST_OUTPUT"
HOME="$TEST_HOME" bash "$REPO_ROOT/install.sh" --plugins --skills >"$SECOND_OUTPUT"

assert_grep 'Mode: symlink' "$SECOND_OUTPUT"
assert_grep 'Installed/updated: 0' "$SECOND_OUTPUT"
assert_grep 'Skipped unchanged: 11' "$SECOND_OUTPUT"

if [[ -L "$TEST_HOME/.opencode/plugin/worktree.ts" ]] && [[ -L "$TEST_HOME/.config/opencode/skills/wisdom" ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "FAIL: default install mode did not produce expected symlinks"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

if [[ ! -e "$TEST_HOME/.config/opencode/opencode.json" ]] && [[ ! -e "$TEST_HOME/.sisyphus/scripts/wisdom-common.sh" ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "FAIL: selective plugin/skill install touched other categories"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

if [[ ! -e "$TEST_HOME/.ez-omo-backup" ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "FAIL: idempotent rerun unexpectedly created backups"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

if [[ "$TESTS_FAILED" -gt 0 ]]; then
    exit 1
fi

exit 0
