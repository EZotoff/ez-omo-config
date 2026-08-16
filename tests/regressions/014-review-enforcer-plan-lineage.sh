#!/usr/bin/env bash
# Regression 014: review-enforcer plan-complete injection must be gated on boulder session lineage.
#
# Bug (2026-08-16, ses_ff594298bffeWXBu7AhWFcF4jk): getPlanProgress() read the
# machine-global ~/.sisyphus/boulder.json — stale since March, active_plan with
# 13/13 checkboxes — and treated ANY session's task() completion as "plan just
# finished". A read-only debate session's near-empty Oracle dispatch (123 chars)
# received the full "ALL PLAN TASKS COMPLETE — full branch review required"
# injection, costing a wasted atlas-review-handler round-trip.
#
# Fix: the plan-complete injection requires (a) the current session to be in
# the boulder's session_ids — mirroring OMO's resolve-active-boulder-session
# predicate, with "opencode:" prefix normalization for legacy bare ids — and
# (b) a status other than paused/abandoned. Completed is allowed: the
# injection fires at the completion moment, before completeBoulder runs.
set -o errexit
source "$(cd "$(dirname "$0")/.." && pwd)/helpers.sh"

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PLUGIN="$REPO_ROOT/plugins/review-enforcer.ts"
HARNESS="$REPO_ROOT/tests/review-enforcer/harness.ts"

assert_file_exists "$PLUGIN"
assert_file_exists "$HARNESS"
command -v bun >/dev/null 2>&1 || { echo "FAIL: bun not found (hard dependency of this config)"; exit 1; }

# Gate wiring must exist in the plugin source...
assert_grep "sessionOwnsBoulder" "$PLUGIN"
assert_grep "boulderStatusAllowsInjection" "$PLUGIN"
assert_grep "getPlanProgress(input.sessionID" "$PLUGIN"

# ...and the gating logic must behave correctly (lineage, normalization, status guard).
if bun "$HARNESS" lineage >/dev/null 2>&1; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "FAIL: review-enforcer lineage harness failed"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

if [[ $TESTS_FAILED -gt 0 ]]; then
    echo "FAILURE: review-enforcer plan-lineage gate missing or broken (see tests/review-enforcer/harness.ts)"
    exit 1
fi
echo "PASS: plan-complete injection gated on boulder session lineage"
