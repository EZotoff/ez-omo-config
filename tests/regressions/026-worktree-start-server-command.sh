#!/usr/bin/env bash
# Regression 024: worktree_start kicks off /start-work via the server-side
# session command endpoint — never via workspace-broadcast TUI events.
#
# Bug class (2026-09-19 veran incident, sibling of regression 023): worktree_start
# POSTed /tui/select-session + /tui/append-prompt + /tui/submit-prompt. All three
# are workspace-broadcast upstream (identical guard in the TUI), so with N
# session-viewing panes attached it would navigate every pane to the new session,
# insert the /start-work text into every buffer, and submit N duplicate turns.
# It was latent only because multi-pane `oa` attaches postdate 2026-09-16.
# Secondary latent bug: with NO TUI attached, append/submit had no consumer and
# /start-work never ran at all.
#
# Fix: POST /session/{id}/command {command:"start-work", arguments:...} — the
# exact endpoint the TUI submit path itself calls after parsing "/cmd args"
# (app prompt-input/submit.ts) — plus ?directory= scoping. Works headless,
# touches zero TUI panes.
set -o errexit
source "$(cd "$(dirname "$0")/.." && pwd)/helpers.sh"

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
command -v bun >/dev/null 2>&1 || { echo "FAIL: bun not found (hard dependency of this config)"; exit 1; }

# 1. No broadcast TUI events may remain anywhere in the plugin.
assert_no_grep 'tui/select-session' "$REPO_ROOT/plugins/worktree.ts"
assert_no_grep 'tui/append-prompt' "$REPO_ROOT/plugins/worktree.ts"
assert_no_grep 'tui/submit-prompt' "$REPO_ROOT/plugins/worktree.ts"

# 2. The server-side command kickoff must be present and directory-scoped.
assert_grep 'command: "start-work"' "$REPO_ROOT/plugins/worktree.ts"
assert_grep 'session/.*\/command\|/command?' "$REPO_ROOT/plugins/worktree.ts"

# 3. The plugin module must still parse and load.
if WORKTREE_PLUGIN_PATH="$REPO_ROOT/plugins/worktree.ts" bun -e 'await import(process.env.WORKTREE_PLUGIN_PATH)';
    then
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "FAIL: worktree.ts no longer loads (syntax or export surface broken)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

if [[ $TESTS_FAILED -gt 0 ]]; then
    echo "FAILURE: worktree_start broadcast regression (see tests/regressions/024-worktree-start-server-command.sh)"
    exit 1
fi
echo "PASS: worktree_start kicks off via server-side command endpoint, zero TUI broadcasts"
