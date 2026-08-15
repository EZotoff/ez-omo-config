#!/usr/bin/env bash
# Kill-proof for 012-pinned-session-race-fix.sh: strip the fix markers from a copy
# of local.tsx and prove the test detects the regression (nonzero exit).
set -o errexit
tmpdir="$(mktemp -d)"; trap 'rm -rf "$tmpdir"' EXIT
SRC="$HOME/src/opencode/packages/tui/src/context/local.tsx"
[[ -f "$SRC" ]] || { echo "SKIP: source not present"; exit 0; }
# Reintroduce the bug shape: sync prune + save(), no merge guard, no RMW
sed -e 's/async function prune/function prune/' \
    -e 's/for (const id of fromFile) if (!merged.includes(id)) merged.push(id)//' \
    -e 's/onDisk.filter((id) => id !== sessionID)/sessionStore.pinned/' \
    "$SRC" > "$tmpdir/local.tsx"
TEST="$(cd "$(dirname "$0")" && pwd)/012-pinned-session-race-fix.sh"
if PIN_RACE_SRC="$tmpdir/local.tsx" bash "$TEST" >/dev/null 2>&1; then
    echo "FAIL: test passed against unfixed source — sentinel broken"
    exit 1
fi
echo "PROVED: pinned-session-race test detects reintroduced bug"
exit 0
