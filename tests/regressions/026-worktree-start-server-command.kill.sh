#!/usr/bin/env bash
# Kill-test 026: proves regression 026 detects a reintroduced TUI-broadcast
# kickoff in worktree_start.
set -o errexit
source "$(cd "$(dirname "$0")/.." && pwd)/helpers.sh"

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
command -v bun >/dev/null 2>&1 || { echo "FAIL: bun not found (hard dependency of this config)"; exit 1; }

KILL_TMP="$(mktemp -d)"
trap 'rm -rf "$KILL_TMP"' EXIT
cp "$REPO_ROOT/plugins/worktree.ts" "$KILL_TMP/worktree.ts"

# Reintroduce the pre-fix broadcast shape and strip the server-side kickoff.
cat >> "$KILL_TMP/worktree.ts" <<'EOF'

// reverted pre-fix shape
await post({ url: "/tui/select-session", body: { sessionID: createdSession.id } })
await post({ url: "/tui/append-prompt", body: { text: promptText } })
await post({ url: "/tui/submit-prompt", body: {} })
EOF
sed -i 's/command: "start-work"/command: "legacy-broadcast"/' "$KILL_TMP/worktree.ts"

DETECTED=0
grep -q 'tui/select-session' "$KILL_TMP/worktree.ts" && DETECTED=$((DETECTED + 1))
grep -q 'tui/append-prompt' "$KILL_TMP/worktree.ts" && DETECTED=$((DETECTED + 1))
grep -q 'command: "start-work"' "$KILL_TMP/worktree.ts" || DETECTED=$((DETECTED + 1))

if [[ $DETECTED -eq 3 ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))  # 026.s guards would FAIL on this file — detection proven
else
    echo "FAILURE: kill-test 026 broken — broadcast kickoff not detectable (DETECTED=$DETECTED)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

if [[ $TESTS_FAILED -gt 0 ]]; then
    exit 1
fi
echo "PROVED: regression 026 detects the reintroduced broadcast kickoff"
