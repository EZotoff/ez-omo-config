#!/usr/bin/env bash
# Regression 033: subagent task fallback retries the SAME session in place,
# and a fallback hop no longer injects a per-hop wake into the parent.
#
# Fix (plan subagent-fallback-rework, todos 1-2, fork commit e01423907 on
# fix/custom-patches-v4.19.2): tryFallbackRetry gained an in-place branch
# (EZ-PATCH: subagent-fallback-inplace in fallback-retry-handler.ts) that
# re-prompts the failed session with the next fallback model, and the
# manager's per-hop "[BACKGROUND TASK RETRYING]" queuePendingParentWake
# injection was replaced by a logger line — the attempt chain reaches the
# parent only via the terminal notification.
#
# Dist bundle note: the dist check SKIPs when dist/index.js is missing or
# provably stale (older than the patched source); the rebuild lands in a
# later plan todo.
set -euo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/helpers.sh"

# Resolve the live OMO install (newest versioned dir), overridable for CI.
OMO_INSTALL="${OMO_INSTALL:-$(ls -d "$HOME"/oh-my-openagent-v* 2>/dev/null | sort -V | tail -1)}"
if [[ -z "$OMO_INSTALL" || ! -d "$OMO_INSTALL" ]]; then
    echo "FAIL: no oh-my-openagent-v* install found under \$HOME (set OMO_INSTALL to override)"
    exit 1
fi
HANDLER="$OMO_INSTALL/packages/omo-opencode/src/features/background-agent/fallback-retry-handler.ts"
MANAGER="$OMO_INSTALL/packages/omo-opencode/src/features/background-agent/manager.ts"
DIST="$OMO_INSTALL/dist/index.js"

assert_file_exists "$HANDLER"
assert_file_exists "$MANAGER"
command -v bun >/dev/null 2>&1 || { echo "FAIL: bun not found (hard dependency of this config)"; exit 1; }

# (a) Source marker: the in-place fallback branch exists in the patched handler.
assert_grep "EZ-PATCH: subagent-fallback-inplace" "$HANDLER"

# (b) The manager's tryFallbackRetry method region carries the hop summary
# only as a logger line — no per-hop queuePendingParentWake injection.
TRY_REGION="$(awk '/private async tryFallbackRetry\(/,/^  markForNotification\(/' "$MANAGER")"
if [[ -z "$TRY_REGION" ]]; then
    echo "FAIL: could not extract tryFallbackRetry method region from $MANAGER"
    TESTS_FAILED=$((TESTS_FAILED + 1))
else
    HOP_WAKES="$(printf '%s\n' "$TRY_REGION" | grep -c "queuePendingParentWake" || true)"
    if [[ "$HOP_WAKES" -gt 0 ]]; then
        echo "FAIL: tryFallbackRetry region still injects per-hop parent wakes ($HOP_WAKES queuePendingParentWake call(s))"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    else
        TESTS_PASSED=$((TESTS_PASSED + 1))
    fi
    if printf '%s\n' "$TRY_REGION" | grep -q "BACKGROUND TASK RETRYING"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "FAIL: hop summary logger line missing from tryFallbackRetry region"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
fi

# (c) Compiled runtime bundle carries the patch — SKIP while the dist is
# missing or provably stale (predates the patched source; rebuild pending).
if [[ ! -f "$DIST" ]]; then
    echo "SKIP: dist bundle not built yet ($DIST)"
elif [[ "$DIST" -ot "$HANDLER" ]]; then
    echo "SKIP: dist bundle predates the patched source (rebuild pending)"
else
    assert_grep "EZ-PATCH: subagent-fallback-inplace" "$DIST"
fi

# (d) Behavioral pin: the focused in-place fallback tests pass against the
# patched source.
if (cd "$OMO_INSTALL/packages/omo-opencode" && bun test src/features/background-agent/fallback-retry-handler.test.ts -t "in-place" >/dev/null 2>&1); then
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "FAIL: focused in-place fallback tests failed (expected all pass, 0 fail)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

if [[ ${TESTS_FAILED:-0} -gt 0 ]]; then
    echo "FAILURE: subagent in-place fallback patch missing or broken in $OMO_INSTALL"
    exit 1
fi
echo "PASS: subagent fallback retries in place without per-hop parent wakes (source + behavioral tests)"
