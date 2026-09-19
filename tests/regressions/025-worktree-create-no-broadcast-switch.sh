#!/usr/bin/env bash
# Regression 025: worktree_create must not broadcast a TUI session switch and
# must not fork twice for the same branch.
#
# Bug (2026-09-19, veran feat/nestor-stats incident): worktree_create POSTed
# /tui/select-session after forking. That event is workspace-broadcast by
# upstream design (packages/opencode handlers/tui.ts publishes TuiEvent.SessionSelect;
# every attached TUI matching the workspace navigates, app.tsx "tui.session.select"),
# so ONE call hijacked every `oa` pane in every project on the interactive daemon.
# Separately, the switch fired mid-turn: the fork was born without the tool result
# or closing summary, looked interrupted, and the user's "continue" landing in the
# fork made its agent re-run worktree_create -> a second fork (no idempotency guard).
#
# Fix (operator decision, option (a)): worktree_create performs NO TUI switch at
# all (the user picks the fork from the session picker; the tool result carries
# the fork ID), and re-uses any fork session already tracked for the branch.
set -o errexit
source "$(cd "$(dirname "$0")/.." && pwd)/helpers.sh"

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
command -v bun >/dev/null 2>&1 || { echo "FAIL: bun not found (hard dependency of this config)"; exit 1; }

# 1. Idempotency guard: a by-branch session lookup must exist in the state
#    module and be consulted by the plugin before forking.
assert_grep 'getSessionByBranch' "$REPO_ROOT/plugins/worktree/state.ts"
assert_grep 'getSessionByBranch' "$REPO_ROOT/plugins/worktree.ts"

# 2. No broadcast session switch may remain in worktree_create. The old switch
#    block's distinctive local (handoffError) existed only there; worktree_start
#    keeps its own (separate, known-broadcast) flow and does not use it.
assert_no_grep 'handoffError' "$REPO_ROOT/plugins/worktree.ts"

# 3. The tool result must carry the reuse contract so agents do not retry forks.
assert_grep 'No new fork created' "$REPO_ROOT/plugins/worktree.ts"

# 4. The plugin module must still parse and load.
if WORKTREE_PLUGIN_PATH="$REPO_ROOT/plugins/worktree.ts" bun -e 'await import(process.env.WORKTREE_PLUGIN_PATH)';
    then
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "FAIL: worktree.ts no longer loads (syntax or export surface broken)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

if [[ $TESTS_FAILED -gt 0 ]]; then
    echo "FAILURE: worktree_create broadcast-switch / double-fork regression (see tests/regressions/025-worktree-create-no-broadcast-switch.sh)"
    exit 1
fi
echo "PASS: worktree_create forks idempotently and never broadcasts a TUI switch"
