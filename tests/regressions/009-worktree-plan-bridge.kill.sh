#!/usr/bin/env bash
# Kill-test for 009-worktree-plan-bridge: proves the .sh test would catch the bug
# if it regressed (i.e., if PLAN_DIRS were reverted to single-directory scanning).
#
# Simulates the bug: a plugin that only scans .sisyphus/plans/ (pre-fix state).
# The structural check for .omo/plans should FAIL — proving the regression would be caught.
set -o errexit
source "$(cd "$(dirname "$0")/.." && pwd)/helpers.sh"
tmpdir="$(mktemp -d)"; trap 'rm -rf "$tmpdir"' EXIT

# Simulate the pre-fix bug: PLAN_DIRS only contains the legacy location
cat > "$tmpdir/worktree-buggy.ts" <<'BUGY'
const PLAN_DIRS = [".sisyphus/plans"]
BUGY

# Run the same structural assertion the positive test uses.
# With the bug present, this MUST fail to find .omo/plans.
assert_grep '\.omo/plans' "$tmpdir/worktree-buggy.ts" >"$tmpdir/assertion" 2>&1 || true

if grep -q 'FAIL: Pattern not found' "$tmpdir/assertion"; then
    echo "PROVED: worktree plan bridge"
    exit 0
fi
echo "FAIL: bridge sentinel not detected — test would miss the regression"
exit 1
