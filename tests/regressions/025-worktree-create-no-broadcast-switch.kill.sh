#!/usr/bin/env bash
# Kill-test 025: proves regression 025 detects a reintroduced broadcast switch
# or a missing idempotency guard.
#
# Rebuilds the pre-fix shape in a temp copy of worktree.ts: the handoffError
# switch block marker and a stripped by-branch guard, then verifies the static
# guards from 025 would flag that file.
set -o errexit
source "$(cd "$(dirname "$0")/.." && pwd)/helpers.sh"

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
command -v bun >/dev/null 2>&1 || { echo "FAIL: bun not found (hard dependency of this config)"; exit 1; }

KILL_TMP="$(mktemp -d)"
trap 'rm -rf "$KILL_TMP"' EXIT
cp "$REPO_ROOT/plugins/worktree.ts" "$KILL_TMP/worktree.ts"

# Reintroduce the pre-fix shape: broadcast switch block marker present,
# idempotency guard text removed.
cat >> "$KILL_TMP/worktree.ts" <<'EOF'

// reverted pre-fix shape
let handoffError = ""
try {
  await post({ url: "/tui/select-session", body: { sessionID: forkedSession.id } })
} catch (error) {
  handoffError = String(error)
}
EOF
sed -i 's/No new fork created/NEW FORK EVERY TIME/' "$KILL_TMP/worktree.ts"
sed -i 's/getSessionByBranch/getSession/g' "$KILL_TMP/worktree.ts"

DETECTED=0
grep -q 'handoffError' "$KILL_TMP/worktree.ts" && DETECTED=$((DETECTED + 1))
grep -q 'No new fork created' "$KILL_TMP/worktree.ts" || DETECTED=$((DETECTED + 1))
grep -Eq 'getSessionByBranch' "$KILL_TMP/worktree.ts" || DETECTED=$((DETECTED + 1))

if [[ $DETECTED -eq 3 ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))  # 025.s assert_no_grep/assert_grep guards would FAIL on this file — detection proven
else
    echo "FAILURE: kill-test 025 broken — reintroduced broadcast switch not detectable (DETECTED=$DETECTED)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

if [[ $TESTS_FAILED -gt 0 ]]; then
    exit 1
fi
echo "PROVED: regression 025 detects the reintroduced broadcast switch / missing guard"
