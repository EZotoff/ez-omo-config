#!/usr/bin/env bash
# Regression 009: worktree_start must bridge plans between .omo/plans/ and .sisyphus/plans/
#
# Bug fixed 2026-08-03: worktree_start's listPlanNames() only scanned .sisyphus/plans/,
# but OMO's /start-work reads .omo/plans/. Plans written by /prometheus-plan (formerly to
# .sisyphus/plans/) were invisible to /start-work after dispatch, causing "could not resolve
# a plan name" or stale execution. The fix scans BOTH directories and auto-copies the
# resolved plan into .omo/plans/ before /start-work runs.
#
# This test guards against regressions that revert to single-directory scanning or remove
# the ensurePlanInOmoDir bridge call.
set -o errexit
source "$(cd "$(dirname "$0")/.." && pwd)/helpers.sh"
PLUGIN="$(cd "$(dirname "$0")/../.." && pwd)/plugins/worktree.ts"
[[ -f "$PLUGIN" ]] || { echo "FAIL: plugins/worktree.ts not found"; exit 1; }

# 1. PLAN_DIRS constant must include BOTH canonical (.omo/plans) and legacy (.sisyphus/plans)
assert_grep '\.omo/plans' "$PLUGIN"
assert_grep '\.sisyphus/plans' "$PLUGIN"

# 2. Bridge helper must exist
assert_grep 'async function ensurePlanInOmoDir' "$PLUGIN"

# 3. worktree_start must call the bridge before dispatching /start-work
assert_grep 'ensurePlanInOmoDir(directory' "$PLUGIN"

# 4. prometheus-plan skill must write new plans to .omo/plans/ (migration completed)
SKILL="$(cd "$(dirname "$0")/../.." && pwd)/../.claude/skills/prometheus-plan/SKILL.md"
# The skill lives outside the repo; skip if absent (e.g., on a fresh clone).
if [[ -f "$SKILL" ]]; then
    assert_grep '\.omo/plans' "$SKILL"
    # New plans must NOT be written to .sisyphus/plans/ anymore
    assert_no_grep 'saved to .sisyphus/plans' "$SKILL"
fi

[[ "$TESTS_FAILED" -gt 0 ]] && { echo "FAIL: worktree plan bridge check(s) failed"; exit 1; }
echo "PASS: worktree plan bridge present"
exit 0
