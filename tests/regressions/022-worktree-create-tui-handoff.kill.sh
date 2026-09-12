#!/usr/bin/env bash
# Kill-test 022: proves regression 022 detects a reintroduced terminal handoff.
#
# Rebuilds the pre-fix shape (openTerminal call + "new terminal" success
# message) in a temp copy of worktree.ts and verifies the static guards flag it.
set -o errexit
source "$(cd "$(dirname "$0")/.." && pwd)/helpers.sh"

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
command -v bun >/dev/null 2>&1 || { echo "FAIL: bun not found (hard dependency of this config)"; exit 1; }

KILL_TMP="$(mktemp -d)"
trap 'rm -rf "$KILL_TMP"' EXIT
cp "$REPO_ROOT/plugins/worktree.ts" "$KILL_TMP/worktree.ts"

# Reintroduce the pre-fix shape: terminal handoff call + success message.
cat >> "$KILL_TMP/worktree.ts" <<'EOF'

// reverted pre-fix shape
const terminalResult = await openTerminal(worktreePath, `opencode --session x`, "branch")
EOF
sed -i 's/No GUI terminal is opened/A new terminal has been opened with OpenCode/' "$KILL_TMP/worktree.ts"

DETECTED=0
grep -q 'openTerminal' "$KILL_TMP/worktree.ts" && DETECTED=$((DETECTED + 1))
grep -q 'A new terminal has been opened' "$KILL_TMP/worktree.ts" && DETECTED=$((DETECTED + 1))

if [[ $DETECTED -eq 2 ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))  # assert_no_grep guards in 022 would FAIL on this file — detection proven
else
    echo "FAILURE: kill-test 022 broken — reintroduced terminal handoff not detectable"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

if [[ $TESTS_FAILED -gt 0 ]]; then
    exit 1
fi
echo "PROVED: regression 022 detects the reintroduced terminal handoff shape"
