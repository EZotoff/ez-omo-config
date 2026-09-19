#!/usr/bin/env bash
# Regression 022: worktree tools never hand off via a GUI terminal.
#
# Bug (2026-09-12): worktree_create forked a session with full context, then
# handed off with openTerminal(worktreePath, "opencode --session <id>") — a GUI
# terminal spawn that (a) silently failed on display-less systemd-launched
# servers (no DISPLAY — see regression 020) and (b) was never the intent:
# the user wants autonomous session handoff, mirroring worktree_start.
#
# Fix: TUI-based handoff replaced the terminal spawn; openTerminal is gone.
# UPDATE (2026-09-19): worktree_create no longer performs ANY TUI switch
# (workspace-broadcast hijack — see regression 025). The select-session grep
# below now guards worktree_start's switch only.
set -o errexit
source "$(cd "$(dirname "$0")/.." && pwd)/helpers.sh"

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
command -v bun >/dev/null 2>&1 || { echo "FAIL: bun not found (hard dependency of this config)"; exit 1; }

# 1. No TUI-session-switch mechanism may remain anywhere (2026-09-19: the
#    select-session broadcast hijacked every attached pane — 023/024 own the
#    replacement contracts).
assert_no_grep 'tui/select-session' "$REPO_ROOT/plugins/worktree.ts"

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
echo "PASS: worktree tools never hand off via GUI terminal or TUI broadcast switch"
