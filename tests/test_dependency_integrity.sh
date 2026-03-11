#!/usr/bin/env bash
set -euo pipefail

source tests/helpers.sh

assert_dir_exists "scripts/wisdom"
assert_file_exists "scripts/wisdom/wisdom-common.sh"

wisdom_dependents=(
    "scripts/wisdom/wisdom-search.sh"
    "scripts/wisdom/wisdom-write.sh"
    "scripts/wisdom/wisdom-sync.sh"
    "scripts/wisdom/wisdom-archive.sh"
    "scripts/wisdom/wisdom-delete.sh"
    "scripts/wisdom/wisdom-edit.sh"
    "scripts/wisdom/wisdom-gc.sh"
    "scripts/wisdom/wisdom-merge.sh"
)

for script in "${wisdom_dependents[@]}"; do
    assert_file_exists "$script"
    assert_grep 'source ".*wisdom-common\.sh"' "$script"
done

assert_dir_exists "plugins"
assert_file_exists "plugins/worktree.ts"
assert_file_exists "plugins/git-safety.ts"
assert_file_exists "plugins/review-enforcer.ts"
assert_file_exists "plugins/README.md"

assert_dir_exists "plugins/worktree"
assert_file_exists "plugins/worktree/state.ts"
assert_file_exists "plugins/worktree/terminal.ts"

assert_dir_exists "plugins/kdco-primitives"
assert_file_exists "plugins/kdco-primitives/index.ts"
assert_file_exists "plugins/kdco-primitives/get-project-id.ts"
assert_file_exists "plugins/kdco-primitives/log-warn.ts"
assert_file_exists "plugins/kdco-primitives/mutex.ts"
assert_file_exists "plugins/kdco-primitives/shell.ts"
assert_file_exists "plugins/kdco-primitives/temp.ts"
assert_file_exists "plugins/kdco-primitives/terminal-detect.ts"
assert_file_exists "plugins/kdco-primitives/types.ts"
assert_file_exists "plugins/kdco-primitives/with-timeout.ts"

assert_grep 'from "\./kdco-primitives/types"' "plugins/worktree.ts"
assert_grep 'from "\./kdco-primitives/get-project-id"' "plugins/worktree.ts"
assert_grep 'from "\./worktree/state"' "plugins/worktree.ts"
assert_grep 'from "\./worktree/terminal"' "plugins/worktree.ts"
assert_grep 'from "\.\./kdco-primitives"' "plugins/worktree/state.ts"
assert_grep 'from "\.\./kdco-primitives"' "plugins/worktree/terminal.ts"
assert_grep 'export type { OpencodeClient } from "\./types"' "plugins/kdco-primitives/index.ts"
assert_grep 'kdco-primitives' "plugins/README.md"
assert_grep 'worktree.ts' "plugins/README.md"
assert_grep 'git-safety.ts' "plugins/README.md"
assert_grep 'review-enforcer.ts' "plugins/README.md"

plugin_sources=(
    "plugins/worktree.ts"
    "plugins/git-safety.ts"
    "plugins/review-enforcer.ts"
    "plugins/worktree/state.ts"
    "plugins/worktree/terminal.ts"
    "plugins/kdco-primitives/index.ts"
    "plugins/kdco-primitives/get-project-id.ts"
    "plugins/kdco-primitives/log-warn.ts"
    "plugins/kdco-primitives/mutex.ts"
    "plugins/kdco-primitives/shell.ts"
    "plugins/kdco-primitives/temp.ts"
    "plugins/kdco-primitives/terminal-detect.ts"
    "plugins/kdco-primitives/types.ts"
    "plugins/kdco-primitives/with-timeout.ts"
)

for plugin_file in "${plugin_sources[@]}"; do
    assert_no_grep '/home/ezotoff' "$plugin_file"
done

if [[ "$TESTS_FAILED" -gt 0 ]]; then
    exit 1
fi

exit 0
