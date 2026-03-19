#!/usr/bin/env bash
set -euo pipefail

source tests/helpers.sh

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_HOME="$(mktemp -d)"
OUTPUT_FILE="$(mktemp)"
COMMANDS_OUTPUT="$(mktemp)"
SCRIPTS_OUTPUT="$(mktemp)"

cleanup() {
    rm -rf "$TEST_HOME" "$OUTPUT_FILE" "$COMMANDS_OUTPUT" "$SCRIPTS_OUTPUT"
}
trap cleanup EXIT

HOME="$TEST_HOME" bash "$REPO_ROOT/install.sh" --dry-run >"$OUTPUT_FILE"
HOME="$TEST_HOME" bash "$REPO_ROOT/install.sh" --dry-run --commands >"$COMMANDS_OUTPUT"
HOME="$TEST_HOME" bash "$REPO_ROOT/install.sh" --dry-run --scripts >"$SCRIPTS_OUTPUT"

assert_grep 'DRY-RUN' "$OUTPUT_FILE"
assert_grep 'commands/models-preset.md' "$OUTPUT_FILE"
assert_grep '\.config/opencode/command/models-preset\.md' "$OUTPUT_FILE"
assert_grep 'configs/opencode/opencode.json' "$OUTPUT_FILE"
assert_grep 'Mode: symlink' "$OUTPUT_FILE"
assert_grep 'Dry run: yes' "$OUTPUT_FILE"
assert_grep 'Backup location:' "$OUTPUT_FILE"
assert_grep 'commands/models-preset.md' "$COMMANDS_OUTPUT"
assert_grep 'Groups: commands' "$COMMANDS_OUTPUT"
assert_grep '\.config/opencode/command/models-preset\.md' "$COMMANDS_OUTPUT"
assert_no_grep 'configs/opencode/opencode.json' "$COMMANDS_OUTPUT"
assert_grep 'scripts/wisdom/wisdom-common.sh' "$SCRIPTS_OUTPUT"
assert_no_grep 'configs/opencode/opencode.json' "$SCRIPTS_OUTPUT"

if [[ -e "$TEST_HOME/.config/opencode/opencode.json" ]]; then
    echo "FAIL: dry run created config target"
    TESTS_FAILED=$((TESTS_FAILED + 1))
else
    TESTS_PASSED=$((TESTS_PASSED + 1))
fi

if [[ -e "$TEST_HOME/.opencode" ]]; then
    echo "FAIL: dry run created target directory"
    TESTS_FAILED=$((TESTS_FAILED + 1))
else
    TESTS_PASSED=$((TESTS_PASSED + 1))
fi

if [[ -e "$TEST_HOME/.ez-omo-backup" ]]; then
    echo "FAIL: dry run created backup directory"
    TESTS_FAILED=$((TESTS_FAILED + 1))
else
    TESTS_PASSED=$((TESTS_PASSED + 1))
fi

if [[ "$TESTS_FAILED" -gt 0 ]]; then
    exit 1
fi

exit 0
