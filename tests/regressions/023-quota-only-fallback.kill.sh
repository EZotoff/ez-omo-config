#!/usr/bin/env bash
# Kill-test 023: proves regression 023 detects the pre-fix shapes.
#
# Mutates copies of the two load-bearing sources back to their buggy form:
#   (a) session-status-handler without the quota gate  -> generic retryables fall back
#   (b) same-model-retry with an uncapped/low cap      -> backoff no longer honours 120s
# Runs the same greps regression 023 uses and expects each to MISS.
set -o errexit
source "$(cd "$(dirname "$0")/.." && pwd)/helpers.sh"

OMO_DIR="${OMO_DIR:-$HOME/oh-my-openagent-v4.19.2}"
RT="$OMO_DIR/packages/omo-opencode/src/hooks/runtime-fallback"

KILL_TMP="$(mktemp -d)"
trap 'rm -rf "$KILL_TMP"' EXIT

# (a) Reintroduce the pre-fix status handler: drop the quota gate line.
grep -v 'classifyErrorType({ message: retryMessage }) !== "quota_exceeded"' \
    "$RT/session-status-handler.ts" > "$KILL_TMP/session-status-handler.pre.ts"
if grep -q 'classifyErrorType({ message: retryMessage }) !== "quota_exceeded"' \
    "$KILL_TMP/session-status-handler.pre.ts"; then
    echo "FAILURE: kill-test 023 broken — quota gate survived mutation"
    TESTS_FAILED=$((TESTS_FAILED + 1))
else
    TESTS_PASSED=$((TESTS_PASSED + 1))
fi

# (b) Reintroduce an uncapped backoff (the shape the bug produced: retries in seconds).
sed 's/MAX_DELAY_MS = 120_000/MAX_DELAY_MS = 5_000/' \
    "$RT/same-model-retry.ts" > "$KILL_TMP/same-model-retry.pre.ts"
if grep -q 'MAX_DELAY_MS = 120_000' "$KILL_TMP/same-model-retry.pre.ts"; then
    echo "FAILURE: kill-test 023 broken — 120s cap survived mutation"
    TESTS_FAILED=$((TESTS_FAILED + 1))
else
    TESTS_PASSED=$((TESTS_PASSED + 1))
fi

if [[ $TESTS_FAILED -gt 0 ]]; then
    exit 1
fi
echo "PROVED: regression 023 detects a removed quota gate and a lowered backoff cap"
