#!/usr/bin/env bash
# Regression 019: unresolved CRITICAL findings must never be silently demoted
# or waved through after review cycle 2.
#
# Bug (2026-09-09): the atlas-review-handler skill's Cycle 2 closeout said
# "Note remaining findings as INFO-level advisories. Proceed to the next
# original task." and its CRITICAL RULES said "After 2 cycles, STOP and proceed
# regardless of findings" — silently laundering unresolved CRITICAL findings
# into advisories. plugins/review-enforcer.ts injected the same semantics
# ("Maximum 2 review cycles, then proceed regardless") into every task
# completion. Both contradicted the final verification wave, which requires
# every reviewer to approve.
#
# Fix: after cycle 2 the handler must adjudicate every remaining CRITICAL
# finding via RULE / BLOCK / PARK closeout (recorded in the plan notepad or,
# without an active plan, the final report). CRITICAL findings are never
# demoted to INFO and never represented as approval.
set -o errexit
source "$(cd "$(dirname "$0")/.." && pwd)/helpers.sh"

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SKILL="$REPO_ROOT/skills/atlas-review-handler/SKILL.md"
ENFORCER="$REPO_ROOT/plugins/review-enforcer.ts"

assert_file_exists "$SKILL"
assert_file_exists "$ENFORCER"

# The closeout contract must be present in the handler skill.
# (Positive checks run FIRST so the RED gate fails on missing new-contract
# text, not on the still-present old text — see Task 1 RED gate.)
assert_grep 'CRITICAL CLOSEOUT' "$SKILL"
assert_grep 'Ruling:' "$SKILL"
assert_grep 'decisions\.md' "$SKILL"
assert_grep 'problems\.md' "$SKILL"
# The enforcer injection must mirror the same contract.
assert_grep 'RULE/BLOCK/PARK' "$ENFORCER"
assert_grep 'never be represented as approval' "$ENFORCER"
# The laundering language must be gone from both surfaces.
assert_no_grep 'proceed regardless' "$SKILL"
assert_no_grep 'INFO-level advisories' "$SKILL"
assert_no_grep 'proceed regardless' "$ENFORCER"

if [[ $TESTS_FAILED -gt 0 ]]; then
    echo "FAILURE: CRITICAL-closeout contract violated (see tests/regressions/019-review-critical-closeout.sh)"
    exit 1
fi
echo "PASS: unresolved CRITICAL findings require RULE/BLOCK/PARK closeout"
