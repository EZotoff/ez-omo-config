#!/usr/bin/env bash
# Kill-proof for regression 2026-08-02-subagent-near-empty-stall: proves the
# test fails when the near-empty detection code is ABSENT from the plugin.
#
# Strategy: build a minimal plugin stub that LACKS the near-empty detection
# branch (no 'near-empty completion flagged' log line, no childSessionVerdictCache,
# no min_output_tokens read), then run the same assert_grep checks against it
# and confirm they produce the FAIL sentinel. This proves the test catches the
# regression it claims to.
set -o errexit
source "$(cd "$(dirname "$0")/.." && pwd)/helpers.sh"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

# Minimal plugin stub: exports the right shape but has NO near-empty detection.
# This is the exact configuration before todo 1's fix — only the zero-token
# branch existed.
mkdir -p "$TMP_ROOT/configs/opencode"
cat >"$TMP_ROOT/configs/opencode/provider-connect-retry.mjs" <<'MJS'
export const ProviderConnectRetryPlugin = async (ctx) => {
  return {
    event: async ({ event }) => {
      // Pre-fix plugin: only zero-token branch, no near-empty detection.
      if (event?.type === "message.updated") {
        const info = event.properties?.info ?? {};
        if (info.role === "assistant" && info.finish && (info.tokens?.output ?? 0) === 0) {
          // zero-token stall handling only
        }
      }
    },
  };
};
MJS

# Run the detection-code assertions against the stub; expect them to FAIL.
# If any of these pass against the stub, the test is broken (it would not
# catch removal of the near-empty code).
BROKEN=0

if assert_grep 'near-empty completion flagged' "$TMP_ROOT/configs/opencode/provider-connect-retry.mjs" >/dev/null 2>&1; then
    echo "KILL-BROKEN: assert_grep found 'near-empty completion flagged' in stub that lacks it"
    BROKEN=1
fi

if assert_grep 'childSessionVerdictCache' "$TMP_ROOT/configs/opencode/provider-connect-retry.mjs" >/dev/null 2>&1; then
    echo "KILL-BROKEN: assert_grep found 'childSessionVerdictCache' in stub that lacks it"
    BROKEN=1
fi

if assert_grep 'min_output_tokens' "$TMP_ROOT/configs/opencode/provider-connect-retry.mjs" >/dev/null 2>&1; then
    echo "KILL-BROKEN: assert_grep found 'min_output_tokens' in stub that lacks it"
    BROKEN=1
fi

if [[ $BROKEN -eq 1 ]]; then
    exit 1
fi

echo "KILL-PROVED: detection-code assertions correctly fail when near-empty branch is absent"
exit 0
