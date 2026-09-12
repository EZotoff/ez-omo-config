#!/usr/bin/env bash
# Regression 022: worktree_create hands off via TUI session switch, not a GUI terminal.
#
# Bug (2026-09-12): worktree_create forked a session with full context, then
# handed off with openTerminal(worktreePath, "opencode --session <id>") — a GUI
# terminal spawn that (a) silently failed on display-less systemd-launched
# servers (no DISPLAY — see regression 020) and (b) was never the intent: the
# user wants autonomous session handoff, mirroring worktree_start.
#
# Fix: worktree_create switches the TUI to the forked session via
# POST /tui/select-session (same mechanism as worktree_start); on failure it
# returns the manual resume command. openTerminal is gone from the plugin.
set -o errexit
source "$(cd "$(dirname "$0")/.." && pwd)/helpers.sh"

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
command -v bun >/dev/null 2>&1 || { echo "FAIL: bun not found (hard dependency of this config)"; exit 1; }

# 1. The TUI handoff mechanism must be present.
assert_grep 'tui/select-session' "$REPO_ROOT/plugins/worktree.ts"

# 2. The terminal handoff must be gone: no openTerminal import/call, no
#    "new terminal" success message in the plugin.
assert_no_grep 'openTerminal' "$REPO_ROOT/plugins/worktree.ts"
assert_no_grep 'A new terminal has been opened' "$REPO_ROOT/plugins/worktree.ts"

# 3. Both worktree tools must expose the autonomous contract in their
#    descriptions (agents steer by description).
assert_grep 'No GUI terminal is opened' "$REPO_ROOT/plugins/worktree.ts"
assert_grep 'Call it with the plan name' "$REPO_ROOT/plugins/worktree.ts"

# 4. The plugin module must still parse and load.
if WORKTREE_PLUGIN_PATH="$REPO_ROOT/plugins/worktree.ts" bun -e 'await import(process.env.WORKTREE_PLUGIN_PATH)';
    then
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "FAIL: worktree.ts no longer loads (syntax or export surface broken)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

if [[ $TESTS_FAILED -gt 0 ]]; then
    echo "FAILURE: worktree create handoff regression (see tests/regressions/022-worktree-create-tui-handoff.sh)"
    exit 1
fi
echo "PASS: worktree_create hands off via TUI session switch (no GUI terminal)"
