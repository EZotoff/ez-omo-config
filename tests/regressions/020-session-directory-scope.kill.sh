#!/usr/bin/env bash
# Kill-proof for 020-session-directory-scope.sh: strip the fix markers from copies
# of sync.tsx / app.tsx and prove the test detects the regression (nonzero exit).
set -o errexit
tmpdir="$(mktemp -d)"; trap 'rm -rf "$tmpdir"' EXIT
SYNC_SRC="$HOME/src/opencode/packages/tui/src/context/sync.tsx"
APP_SRC="$HOME/src/opencode/packages/tui/src/app.tsx"
[[ -f "$SYNC_SRC" && -f "$APP_SRC" ]] || { echo "SKIP: sources not present"; exit 0; }
# Reintroduce the bug shapes: project-wide subtree query, no event insert guard,
# old toggle wording
sed -e 's/return {}/return { path: "" }/' \
    -e 's/directory !== sdk.directory/directory !== "no-match-placeholder"/' \
    "$SYNC_SRC" > "$tmpdir/sync.tsx"
sed -e 's/Limit session list to current directory/Enable session directory filtering/' \
    "$APP_SRC" > "$tmpdir/app.tsx"
TEST="$(cd "$(dirname "$0")" && pwd)/020-session-directory-scope.sh"
if SESSION_SCOPE_SYNC_SRC="$tmpdir/sync.tsx" SESSION_SCOPE_APP_SRC="$tmpdir/app.tsx" \
    bash "$TEST" >/dev/null 2>&1; then
    echo "FAIL: test passed against unfixed source — sentinel broken"
    exit 1
fi
echo "PROVED: session-directory-scope test detects reintroduced bug"
exit 0
