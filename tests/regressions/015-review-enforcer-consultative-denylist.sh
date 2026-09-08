#!/usr/bin/env bash
# Regression 015: review-enforcer must skip consultative subagent dispatches.
#
# Bug (2026-08-16, ses_ff594298bffeWXBu7AhWFcF4jk): every successful task()
# completion received the "you MUST trigger a review" mandate, including
# consultative dispatches. A re-dispatched Oracle debate proposal (48KB of
# analysis, zero code changes) got a code-review mandate appended, injecting
# review noise into the debate context.
#
# Fix: dispatches whose subagent_type (or legacy agent field) targets a
# consultative subagent — oracle, metis, momus, explore, librarian,
# multimodal-looker, document-writer — are skipped: analysis work has no
# implementation to review. Absent/unknown types default to fire (conservative).
set -o errexit
source "$(cd "$(dirname "$0")/.." && pwd)/helpers.sh"

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PLUGIN="$REPO_ROOT/plugins/review-enforcer.ts"
HARNESS="$REPO_ROOT/tests/review-enforcer/harness.ts"
HELPERS="$REPO_ROOT/plugins/review-enforcer/helpers.ts"

assert_file_exists "$PLUGIN"
assert_file_exists "$HARNESS"
assert_file_exists "$HELPERS"
command -v bun >/dev/null 2>&1 || { echo "FAIL: bun not found (hard dependency of this config)"; exit 1; }

# Gate wiring must exist in the plugin source...
assert_grep "CONSULTATIVE_SUBAGENT_TYPES" "$HELPERS"
assert_grep "isConsultativeDispatch" "$PLUGIN"

# ...and the denylist must behave correctly (skips consultative, fires for implementation).
if bun "$HARNESS" consultative >/dev/null 2>&1; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "FAIL: review-enforcer consultative harness failed"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

if [[ $TESTS_FAILED -gt 0 ]]; then
    echo "FAILURE: review-enforcer consultative denylist missing or broken (see tests/review-enforcer/harness.ts)"
    exit 1
fi
echo "PASS: consultative subagent dispatches skip review injection"
