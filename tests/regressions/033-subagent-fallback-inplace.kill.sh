#!/usr/bin/env bash
# Kill-test 033: proves regression 033 detects the pre-fix state.
#
# Uses the preserved pre-fix artifacts: the pre-patch source revision
# (git commit e01423907^ on fix/custom-patches-v4.19.2 — the commit that
# introduced the in-place fallback) and the pre-patch dist bundle
# (dist/index.js.pre-subagent-fallback-inplace, captured at the rebuild
# todo). If neither is available (fresh install, history rewritten), SKIP
# like kill-test 017.
set -euo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/helpers.sh"

OMO_INSTALL="${OMO_INSTALL:-$(ls -d "$HOME"/oh-my-openagent-v* 2>/dev/null | sort -V | tail -1)}"
if [[ -z "$OMO_INSTALL" || ! -d "$OMO_INSTALL" ]]; then
    echo "SKIP: no oh-my-openagent-v* install found under \$HOME"
    exit 0
fi
BACKUP_DIST="$OMO_INSTALL/dist/index.js.pre-subagent-fallback-inplace"
PRE_FIX_COMMIT="e01423907^"
HANDLER_REL="packages/omo-opencode/src/features/background-agent/fallback-retry-handler.ts"
MANAGER_REL="packages/omo-opencode/src/features/background-agent/manager.ts"

# At least one pre-fix artifact must exist, else the kill-test cannot run.
if [[ ! -f "$BACKUP_DIST" ]] && ! git -C "$OMO_INSTALL" cat-file -e "$PRE_FIX_COMMIT:$HANDLER_REL" 2>/dev/null; then
    echo "SKIP: no pre-fix artifacts (backup bundle or git history) found in $OMO_INSTALL"
    exit 0
fi

# Pre-fix dist bundle lacks the patch literal → the regression's dist-grep
# would fail against it.
if [[ -f "$BACKUP_DIST" ]]; then
    assert_no_grep "EZ-PATCH: subagent-fallback-inplace" "$BACKUP_DIST"
fi

# Pre-fix source revision lacks the in-place marker, and its manager still
# injects the per-hop "[BACKGROUND TASK RETRYING]" wake via
# queuePendingParentWake inside tryFallbackRetry → both the marker and the
# hop-wake assertions of regression 033 fail against it.
if git -C "$OMO_INSTALL" cat-file -e "$PRE_FIX_COMMIT:$HANDLER_REL" 2>/dev/null; then
    HANDLER_TMP="$(mktemp)"
    MANAGER_TMP="$(mktemp)"
    trap 'rm -f "$HANDLER_TMP" "$MANAGER_TMP"' EXIT
    git -C "$OMO_INSTALL" show "$PRE_FIX_COMMIT:$HANDLER_REL" > "$HANDLER_TMP"
    git -C "$OMO_INSTALL" show "$PRE_FIX_COMMIT:$MANAGER_REL" > "$MANAGER_TMP"
    assert_no_grep "EZ-PATCH: subagent-fallback-inplace" "$HANDLER_TMP"
    TRY_REGION="$(awk '/private async tryFallbackRetry\(/,/^  markForNotification\(/' "$MANAGER_TMP")"
    HOP_WAKES="$(printf '%s\n' "$TRY_REGION" | grep -c "queuePendingParentWake" || true)"
    if [[ "$HOP_WAKES" -gt 0 ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "FAIL: pre-fix tryFallbackRetry region unexpectedly has no queuePendingParentWake hop"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
fi

if [[ ${TESTS_FAILED:-0} -gt 0 ]]; then
    echo "FAILURE: pre-fix artifacts unexpectedly contain subagent-fallback-inplace markers"
    exit 1
fi
echo "PROVED: regression 033 detects the pre-fix state (in-place marker absent, per-hop wake present in pre-patch source)"
