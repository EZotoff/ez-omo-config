#!/usr/bin/env bash
# Regression 023: only quota exhaustion may switch models.
#
# Bug (2026-09-14): Z.AI's coding plan throttles CONCURRENT requests and returns
# "Rate limit reached for requests" — not quota exhaustion. OMO's runtime-fallback
# classified it as a generic retryable error, aborted OpenCode's same-model retry,
# and switched glm-5.3-flash -> gpt-5.6-sol (whose own limit was exhausted, so the
# cascade walked on to ollama-cloud/deepseek). Observed 07:44:55-07:45:28Z in
# ses_f6324747dffegogA2yegTFrx9u and 18 Z.AI attempts/4min in
# ses_f63377bbeffeUe9g0SxOmUZB3x on 2026-09-13.
#
# Contract: quota_exceeded advances fallback_models; every other retryable error
# keeps retrying the SAME model with exponential backoff capped at 120 s.
set -o errexit
source "$(cd "$(dirname "$0")/.." && pwd)/helpers.sh"

OMO_DIR="${OMO_DIR:-$HOME/oh-my-openagent-v4.19.2}"
RT="$OMO_DIR/packages/omo-opencode/src/hooks/runtime-fallback"

assert_file_exists "$RT/session-status-handler.ts"
assert_file_exists "$RT/event-handler.ts"
assert_file_exists "$RT/message-update-handler.ts"
assert_file_exists "$RT/same-model-retry.ts"
assert_file_exists "$OMO_DIR/dist/index.js"

# The three event paths must gate fallback on quota_exceeded...
assert_grep 'classifyErrorType({ message: retryMessage }) !== "quota_exceeded"' "$RT/session-status-handler.ts"
assert_grep 'errorType !== "quota_exceeded"' "$RT/event-handler.ts"
# ...and the scheduler must cap the backoff at 120 s.
assert_grep 'MAX_DELAY_MS = 120_000' "$RT/same-model-retry.ts"
assert_grep 'session.error.same-model' "$RT/same-model-retry.ts"
# The rebuilt bundle must carry the same-model dispatch path.
assert_grep 'session.error.same-model' "$OMO_DIR/dist/index.js"

# Behavior lock: the focused suite must pass (routing contract under fake clock).
if (cd "$OMO_DIR" && bun test \
    packages/omo-opencode/src/hooks/runtime-fallback/same-model-retry.test.ts \
    packages/omo-opencode/src/hooks/runtime-fallback/session-status-handler.test.ts \
    packages/omo-opencode/src/hooks/runtime-fallback/event-handler.test.ts \
    packages/omo-opencode/src/hooks/runtime-fallback/message-update-handler.test.ts >/dev/null 2>&1); then
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "FAIL: focused runtime-fallback tests failed (quota-only + same-model contract broken)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

if [[ $TESTS_FAILED -gt 0 ]]; then
    echo "FAILURE: quota-only fallback contract violated (see tests/regressions/023-quota-only-fallback.sh)"
    exit 1
fi
echo "PASS: fallback gated to quota_exceeded; same-model retry capped at 120s"
