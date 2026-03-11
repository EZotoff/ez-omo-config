#!/usr/bin/env bash
set -euo pipefail

source tests/helpers.sh

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SYMLINK_HOME="$(mktemp -d)"
COPY_HOME="$(mktemp -d)"
SYMLINK_OUTPUT="$(mktemp)"
COPY_OUTPUT="$(mktemp)"

cleanup() {
    rm -rf "$SYMLINK_HOME" "$COPY_HOME" "$SYMLINK_OUTPUT" "$COPY_OUTPUT"
}
trap cleanup EXIT

mkdir -p "$SYMLINK_HOME/.config/opencode"
printf 'old config\n' > "$SYMLINK_HOME/.config/opencode/opencode.json"

HOME="$SYMLINK_HOME" bash "$REPO_ROOT/install.sh" --symlink --configs >"$SYMLINK_OUTPUT"

SYMLINK_TARGET="$SYMLINK_HOME/.config/opencode/opencode.json"
assert_file_exists "$SYMLINK_TARGET"
assert_grep 'Backups created: 1' "$SYMLINK_OUTPUT"

if [[ -L "$SYMLINK_TARGET" ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "FAIL: symlink mode did not create symlink: $SYMLINK_TARGET"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

shopt -s nullglob
backup_matches=("$SYMLINK_HOME/.ez-omo-backup"/*/.config/opencode/opencode.json)
shopt -u nullglob

if [[ ${#backup_matches[@]} -eq 1 ]] && grep -q 'old config' "${backup_matches[0]}"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "FAIL: symlink mode did not preserve previous file in backup"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

HOME="$COPY_HOME" bash "$REPO_ROOT/install.sh" --copy --configs >"$COPY_OUTPUT"

COPY_TARGET="$COPY_HOME/.config/opencode/opencode.json"
assert_file_exists "$COPY_TARGET"
assert_grep 'Mode: copy' "$COPY_OUTPUT"

if [[ ! -L "$COPY_TARGET" ]] && cmp -s "$REPO_ROOT/configs/opencode/opencode.json" "$COPY_TARGET"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "FAIL: copy mode did not create matching regular file: $COPY_TARGET"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

if [[ -f "$COPY_HOME/.opencode/ocx.jsonc" && ! -e "$COPY_HOME/.sisyphus/scripts/wisdom-common.sh" ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "FAIL: configs selection did not stay scoped to config targets"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

if [[ "$TESTS_FAILED" -gt 0 ]]; then
    exit 1
fi

exit 0
