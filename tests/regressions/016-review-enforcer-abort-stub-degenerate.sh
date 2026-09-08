#!/usr/bin/env bash
# Regression 016: review-enforcer must not stamp review mandates on dead tasks
# or category-routed consultative dispatches.
#
# Bug (2026-08-19, ses_fe70ade00ffejSICNMoYyzbb6i, call_6b6c77df): a debate
# critique dispatched via task(category="mephistopheles") died of provider
# exhaustion (4 models, each killed at the 30s runtime-fallback timeout ->
# "Max fallback attempts reached" -> MessageAbortedError). OMO's task tool
# returned a 123-char abort stub ('Aborted\n\nto continue: task(task_id=...')
# which the enforcer processed as a SUCCESS: no failure marker matched
# "Aborted", the consultative gate only read subagent_type/agent (not
# category), and 1343 chars of "Task completed successfully ... you MUST
# trigger a review" were appended to the corpse. The continuation call that
# recovered the real critique was injected a second time.
#
# Fix (three guards):
#   1. abort-stub detection: outputs starting with "Aborted" or containing
#      OMO's continuation-stub signature are treated as failures -> SKIP
#   2. degenerate-output guard: outputs < 250 chars without the success
#      indicator carry no reviewable work -> SKIP
#   3. category-aware consultative gate: category="mephistopheles" joins the
#      denylist; debate judge categories (artistry/writing/ultrabrain) are
#      covered by a [DEBATE] marker in the debate skill's dispatch prompts
#      (same skip mechanism as [REVIEW-TASK]/[REVIEW-FIX]).
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

# Guard wiring must exist in the plugin source...
assert_grep "isAbortStub" "$PLUGIN"
assert_grep "isDegenerateOutput" "$PLUGIN"
assert_grep "CONSULTATIVE_CATEGORIES" "$HELPERS"
assert_grep '"\[DEBATE\]"' "$HELPERS"

# ...and the guards must behave correctly (stub detection, degenerate guard,
# [DEBATE] marker, mephistopheles category).
if bun "$HARNESS" abort >/dev/null 2>&1; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "FAIL: review-enforcer abort/degenerate/category harness failed"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# The debate skill must carry [DEBATE] markers on its dispatch prompts.
DEBATE_SKILL="$REPO_ROOT/skills/debate/SKILL.md"
assert_file_exists "$DEBATE_SKILL"
assert_grep '\[DEBATE\]' "$DEBATE_SKILL"

if [[ $TESTS_FAILED -gt 0 ]]; then
    echo "FAILURE: review-enforcer abort-stub/degenerate/category guards missing or broken (see tests/review-enforcer/harness.ts)"
    exit 1
fi
echo "PASS: abort stubs, degenerate outputs, and [DEBATE]/mephistopheles dispatches skip review injection"
