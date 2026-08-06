#!/usr/bin/env bash
# Regression 011: git-safety.ts MUST detect history-rewrite commands
# and must check git state at the bash command's actual cwd, not at
# ctx.directory.
#
# Bug fixed 2026-08-06 (Fix A + Fix B): git-safety.ts only blocked
# destructive git commands when the working tree was DIRTY. After
# committing, the tree is clean → `git reset --hard <ref>` to discard
# commits, `git commit --amend`, `git rebase`, `git push --force*`,
# `git branch -D`, `git stash clear`, `git reflog expire`, `git gc
# --prune=now` all passed through. Additionally, ctx.directory was used
# for the dirty-tree check, but agents operate in worktrees via bash
# cwd — the guard was structurally inert for ALL worktree work.
#
# Forensic origin: veran feat/compounding-capture-additions, ses_02c3a15e.
# Agent committed clean work, ran `git revert` twice (additive), changed
# its mind, then `git reset --hard 8e69813e` to discard the reverts. Tree
# was clean → guard allowed it → 2 commits orphaned. This regression
# ensures the new HISTORY_REWRITE_PATTERNS layer and worktree-aware
# workdir resolution cannot silently regress.

set -o errexit
source "$(cd "$(dirname "$0")/.." && pwd)/helpers.sh"
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PLUGIN_FILE="$REPO_ROOT/plugins/git-safety.ts"

[[ -f "$PLUGIN_FILE" ]] || { echo "FAIL: plugins/git-safety.ts not found at $PLUGIN_FILE"; exit 1; }
assert_file_exists "$PLUGIN_FILE"

# 1. History-rewrite layer (Fix B) — the new structures must exist.
assert_grep 'HISTORY_REWRITE_PATTERNS' "$PLUGIN_FILE"
assert_grep 'detectHistoryRewriteCommand' "$PLUGIN_FILE"
assert_grep 'detectResetRewrite' "$PLUGIN_FILE"
assert_grep 'LAYER 1.5' "$PLUGIN_FILE"

# 2. Worktree-aware workdir resolution (Fix A) — the new helpers must exist.
assert_grep 'resolveWorkdir' "$PLUGIN_FILE"
assert_grep 'parseLeadingCd' "$PLUGIN_FILE"

# 3. Layer 2 must check git state at `workdir`, not at `directory`.
#    These are the exact lines that were structurally inert in the veran
#    incident. If a future refactor reverts them, the worktree blind-spot
#    comes back.
assert_grep 'isInGitRepo(workdir)' "$PLUGIN_FILE"
assert_grep 'gitStatus(workdir)' "$PLUGIN_FILE"
assert_grep 'gitStashPush(workdir' "$PLUGIN_FILE"

# 4. The ancestor check for `git reset <ref>` (the dominant post-commit
#    destructive pattern) must exist.
assert_grep 'merge-base' "$PLUGIN_FILE"
assert_grep 'is-ancestor' "$PLUGIN_FILE"

# 5. The specific rewrite patterns that catch each destructive class must
#    be present. If any are removed, that class of history rewrite passes
#    through the guard.
assert_grep 'commit --amend' "$PLUGIN_FILE"
assert_grep 'rebase' "$PLUGIN_FILE"
assert_grep 'force-with-lease' "$PLUGIN_FILE"
assert_grep 'branch -D' "$PLUGIN_FILE"
assert_grep 'stash clear' "$PLUGIN_FILE"
assert_grep 'reflog expire' "$PLUGIN_FILE"
assert_grep 'prune' "$PLUGIN_FILE"

# 7. Commit-message payload stripping (Fix C) must exist — without it, any
#    commit message that mentions a destructive command false-positives and
#    blocks the commit itself. (Empirically observed twice during A+B dev.)
assert_grep 'stripCommitMessagePayloads' "$PLUGIN_FILE"
# 6. The __test__ export must exist for the runtime unit harness
#    (tests/git-safety/harness.ts). If it's removed, the unit harness
#    silently stops testing the actual plugin code.
assert_grep 'export const __test__' "$PLUGIN_FILE"

[[ "$TESTS_FAILED" -gt 0 ]] && { echo "FAIL: git-safety history-rewrite check(s) failed"; exit 1; }
echo "PASS: git-safety.ts has history-rewrite layer + worktree-aware workdir resolution"
exit 0
