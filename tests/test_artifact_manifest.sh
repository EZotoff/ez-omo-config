#!/usr/bin/env bash

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/helpers.sh"

assert_path_absent() {
    local path="$1"

    if [[ -e "$path" ]]; then
        echo "FAIL: Path unexpectedly exists: ${path#$REPO_ROOT/}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi

    TESTS_PASSED=$((TESTS_PASSED + 1))
    return 0
}

assert_manifest_row() {
    local pattern="$1"
    assert_grep "$pattern" "$REPO_ROOT/MANIFEST.md"
}

inventory_file="$(mktemp)"
trap 'rm -f "$inventory_file"' EXIT

(
    cd "$REPO_ROOT" || exit 1
    find . -mindepth 1 \( -path './.git' -o -path './.git/*' \) -prune -o -print | sed 's|^./||' | sort
) > "$inventory_file"

assert_file_exists "$REPO_ROOT/MANIFEST.md"
assert_dir_exists "$REPO_ROOT/commands"
assert_dir_exists "$REPO_ROOT/configs"
assert_dir_exists "$REPO_ROOT/configs/opencode"
assert_dir_exists "$REPO_ROOT/configs/oh-my-opencode"
assert_dir_exists "$REPO_ROOT/plugins"
assert_dir_exists "$REPO_ROOT/extras"

assert_manifest_row 'models-preset.md.*commands/'
assert_manifest_row 'opencode.json.*configs/opencode/'
assert_manifest_row 'opencode.jsonc.*configs/opencode/'
assert_manifest_row 'provider-connect-retry.mjs.*configs/opencode/'
assert_manifest_row 'oh-my-opencode.json.*configs/oh-my-opencode/'
assert_manifest_row 'worktree.ts.*plugins/'
assert_manifest_row 'git-safety.ts.*plugins/'
assert_manifest_row 'review-enforcer.ts.*plugins/'
assert_manifest_row 'kdco-primitives/.*plugins/kdco-primitives/'
assert_manifest_row 'ocx.jsonc.*extras/'

assert_file_exists "$REPO_ROOT/commands/models-preset.md"
assert_file_exists "$REPO_ROOT/configs/opencode/opencode.json"
assert_file_exists "$REPO_ROOT/configs/opencode/opencode.jsonc"
assert_file_exists "$REPO_ROOT/configs/opencode/provider-connect-retry.mjs"
assert_file_exists "$REPO_ROOT/configs/opencode/README.md"
assert_file_exists "$REPO_ROOT/configs/oh-my-opencode/oh-my-opencode.json"
assert_file_exists "$REPO_ROOT/extras/ocx.jsonc"

assert_grep '\$HOME/.config/opencode/opencode.json' "$REPO_ROOT/configs/opencode/README.md"
assert_grep '\$HOME/.opencode/opencode.jsonc' "$REPO_ROOT/configs/opencode/README.md"
assert_grep '\$HOME/.config/opencode/provider-connect-retry.mjs' "$REPO_ROOT/configs/opencode/README.md"
assert_grep '\$HOME/.opencode/ocx.jsonc' "$REPO_ROOT/configs/opencode/README.md"

assert_no_grep '/home/ezotoff' "$REPO_ROOT/commands/models-preset.md"
assert_no_grep '/home/ezotoff' "$REPO_ROOT/configs/opencode/opencode.json"
assert_no_grep '/home/ezotoff' "$REPO_ROOT/configs/opencode/opencode.jsonc"
assert_no_grep '/home/ezotoff' "$REPO_ROOT/configs/opencode/provider-connect-retry.mjs"
assert_no_grep '/home/ezotoff' "$REPO_ROOT/extras/ocx.jsonc"

assert_no_grep 'sk-' "$REPO_ROOT/commands/models-preset.md"
assert_no_grep 'sk-' "$REPO_ROOT/configs/opencode/opencode.json"
assert_no_grep 'sk-' "$REPO_ROOT/configs/opencode/opencode.jsonc"
assert_no_grep 'sk-' "$REPO_ROOT/configs/opencode/provider-connect-retry.mjs"
assert_no_grep 'sk-' "$REPO_ROOT/extras/ocx.jsonc"
assert_no_grep 'OPENAI_API' "$REPO_ROOT/commands/models-preset.md"
assert_no_grep 'OPENAI_API' "$REPO_ROOT/configs/opencode/opencode.json"
assert_no_grep 'OPENAI_API' "$REPO_ROOT/configs/opencode/opencode.jsonc"
assert_no_grep 'OPENAI_API' "$REPO_ROOT/configs/opencode/provider-connect-retry.mjs"
assert_no_grep 'OPENAI_API' "$REPO_ROOT/extras/ocx.jsonc"
assert_no_grep 'ghp_' "$REPO_ROOT/commands/models-preset.md"
assert_no_grep 'ghp_' "$REPO_ROOT/configs/opencode/opencode.json"
assert_no_grep 'ghp_' "$REPO_ROOT/configs/opencode/opencode.jsonc"
assert_no_grep 'ghp_' "$REPO_ROOT/configs/opencode/provider-connect-retry.mjs"
assert_no_grep 'ghp_' "$REPO_ROOT/extras/ocx.jsonc"
assert_no_grep 'AIza' "$REPO_ROOT/commands/models-preset.md"
assert_no_grep 'AIza' "$REPO_ROOT/configs/opencode/opencode.json"
assert_no_grep 'AIza' "$REPO_ROOT/configs/opencode/opencode.jsonc"
assert_no_grep 'AIza' "$REPO_ROOT/configs/opencode/provider-connect-retry.mjs"
assert_no_grep 'AIza' "$REPO_ROOT/extras/ocx.jsonc"
assert_no_grep 'BEGIN RSA PRIVATE KEY' "$REPO_ROOT/commands/models-preset.md"
assert_no_grep 'BEGIN RSA PRIVATE KEY' "$REPO_ROOT/configs/opencode/opencode.json"
assert_no_grep 'BEGIN RSA PRIVATE KEY' "$REPO_ROOT/configs/opencode/opencode.jsonc"
assert_no_grep 'BEGIN RSA PRIVATE KEY' "$REPO_ROOT/configs/opencode/provider-connect-retry.mjs"
assert_no_grep 'BEGIN RSA PRIVATE KEY' "$REPO_ROOT/extras/ocx.jsonc"
assert_no_grep 'BEGIN OPENSSH PRIVATE KEY' "$REPO_ROOT/commands/models-preset.md"
assert_no_grep 'BEGIN OPENSSH PRIVATE KEY' "$REPO_ROOT/configs/opencode/opencode.json"
assert_no_grep 'BEGIN OPENSSH PRIVATE KEY' "$REPO_ROOT/configs/opencode/opencode.jsonc"
assert_no_grep 'BEGIN OPENSSH PRIVATE KEY' "$REPO_ROOT/configs/opencode/provider-connect-retry.mjs"
assert_no_grep 'BEGIN OPENSSH PRIVATE KEY' "$REPO_ROOT/extras/ocx.jsonc"

if [[ -f "$REPO_ROOT/plugins/worktree.ts" || -f "$REPO_ROOT/plugins/git-safety.ts" || -f "$REPO_ROOT/plugins/review-enforcer.ts" ]]; then
    assert_file_exists "$REPO_ROOT/plugins/worktree.ts"
    assert_file_exists "$REPO_ROOT/plugins/worktree/state.ts"
    assert_file_exists "$REPO_ROOT/plugins/worktree/terminal.ts"
    assert_file_exists "$REPO_ROOT/plugins/git-safety.ts"
    assert_file_exists "$REPO_ROOT/plugins/review-enforcer.ts"
    assert_dir_exists "$REPO_ROOT/plugins/kdco-primitives"
    assert_file_exists "$REPO_ROOT/plugins/kdco-primitives/get-project-id.ts"
    assert_file_exists "$REPO_ROOT/plugins/kdco-primitives/index.ts"
    assert_file_exists "$REPO_ROOT/plugins/kdco-primitives/log-warn.ts"
    assert_file_exists "$REPO_ROOT/plugins/kdco-primitives/mutex.ts"
    assert_file_exists "$REPO_ROOT/plugins/kdco-primitives/shell.ts"
    assert_file_exists "$REPO_ROOT/plugins/kdco-primitives/temp.ts"
    assert_file_exists "$REPO_ROOT/plugins/kdco-primitives/terminal-detect.ts"
    assert_file_exists "$REPO_ROOT/plugins/kdco-primitives/types.ts"
    assert_file_exists "$REPO_ROOT/plugins/kdco-primitives/with-timeout.ts"
fi

assert_path_absent "$REPO_ROOT/extras/ocx"
assert_path_absent "$REPO_ROOT/ocx"
assert_path_absent "$REPO_ROOT/dashboard"
assert_path_absent "$REPO_ROOT/omo-dashboard"
assert_no_grep '^extras/ocx/' "$inventory_file"
assert_no_grep '^ocx/' "$inventory_file"
assert_no_grep '^dashboard/' "$inventory_file"
assert_no_grep '/dashboard/' "$inventory_file"
assert_no_grep '^omo-dashboard/' "$inventory_file"
assert_no_grep '/omo-dashboard/' "$inventory_file"

echo "Artifact manifest checks: $TESTS_PASSED passed, $TESTS_FAILED failed"

if [[ $TESTS_FAILED -gt 0 ]]; then
    exit 1
fi

exit 0
