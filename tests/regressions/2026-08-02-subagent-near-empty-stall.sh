#!/usr/bin/env bash
# Regression 2026-08-02-subagent-near-empty-stall: the near-empty detection
# branch in provider-connect-retry.mjs MUST be present and the unit harness
# MUST pass.
#
# Bug fixed 2026-08-02 (todo 1 of subagent-stall-harness-fixes, commit 72ef11e):
# the retry plugin only caught ZERO-token completions (finish="other"|"stop"
# AND tokens.output === 0). GLM-5.2 child sessions were stalling with a tiny
# non-zero output (1-5 tokens) and finishing with finish="stop" — below the
# zero-token threshold but above no threshold at all. These near-empty stalls
# on child sessions were silently ignored, defeating the retry+fallback chain
# for the exact scenario it was built for.
#
# The fix added a near-empty branch: on child sessions (parentID set) with
# output tokens in (0, min_output_tokens], the plugin flags the completion
# for retry exactly like a zero-token stall. The threshold comes from the
# registry's `min_output_tokens` field (5 on glm-unknown-api-rejection). Root
# sessions are excluded to avoid false positives on terse-but-valid interactive
# turns.
#
# This test guards against silent removal of either the detection code or the
# unit harness that proves it works.
set -o errexit
source "$(cd "$(dirname "$0")/.." && pwd)/helpers.sh"
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PLUGIN_FILE="$REPO_ROOT/configs/opencode/provider-connect-retry.mjs"
HARNESS="$REPO_ROOT/tests/test_provider_connect_retry_min_output.sh"

[[ -f "$PLUGIN_FILE" ]] || { echo "FAIL: provider-connect-retry.mjs not found at $PLUGIN_FILE"; exit 1; }
[[ -f "$HARNESS" ]]     || { echo "FAIL: test wrapper not found at $HARNESS"; exit 1; }

# 1. The near-empty detection code MUST be present.
#    This signature log line is the grep gate target from todo 1's acceptance criteria.
assert_grep 'near-empty completion flagged' "$PLUGIN_FILE"

# 2. The child-session verdict cache MUST be present (the per-session cache
#    that avoids re-resolving parentID on every completion event). If a future
#    refactor removes it, the near-empty branch cannot distinguish child from
#    root sessions.
assert_grep 'childSessionVerdictCache' "$PLUGIN_FILE"

# 3. The registry field that controls the threshold MUST be read by the plugin.
#    Without this read, min_output_tokens is dead config and the branch always
#    falls back to the default of 5 — silently diverging from the registry.
assert_grep 'min_output_tokens' "$PLUGIN_FILE"

# 4. The unit harness MUST pass end-to-end. This is the proof that the six
#    scenarios (H1-H6) all behave correctly against the real plugin code.
if ! bash "$HARNESS" >/dev/null 2>&1; then
    echo "FAIL: near-empty detection harness did not pass"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

[[ "$TESTS_FAILED" -gt 0 ]] && { echo "FAIL: near-empty detection regression check(s) failed"; exit 1; }
echo "PASS: near-empty detection code present and H1-H6 harness green"
exit 0
