#!/usr/bin/env bash
# test_resume_dispatch_timeout.sh — assert the standalone resume dispatch path
# uses the same 10s per-call curl cap as hook mode (parity with commit 5e819c6).
#
# Guards against regression to the old 5s cap that caused resume dispatch
# timeouts against just-restarted servers (2026-09-28 incident: six prompt_async
# POSTs timed out at 5s during post-restart warmup).
#
# Checks:
#   1. scripts/restart-with-continuation.sh contains exactly two dispatch call
#      sites using the rem2 budget expression
#   2. BOTH sites cap at >=10 seconds (min(10, rem2) or higher)
#   3. No residual min(5, int(rem2)) dispatch cap remains in prompt_async paths

set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/scripts/restart-with-continuation.sh"
[[ -r "$SCRIPT" ]] || { echo "FAIL: cannot read $SCRIPT"; exit 1; }

fail=0

# 1. exactly two rem2-capped dispatch sites
sites=$(grep -c 'min([0-9]\+, int(rem2))\|min([0-9]\+, int(rem2))' "$SCRIPT" || true)
if [[ "$sites" -ne 2 ]]; then
    echo "FAIL: expected exactly 2 rem2-capped dispatch sites, found $sites"
    fail=1
fi

# 2. both caps are >= 10
caps_ge_10=$(grep -c 'min(10, int(rem2))' "$SCRIPT" || true)
if [[ "$caps_ge_10" -ne 2 ]]; then
    echo "FAIL: expected both dispatch caps to be min(10, int(rem2)), found $caps_ge_10"
    fail=1
fi

# 3. no residual 5s cap on rem2 dispatch
residual=$(grep -c 'min(5, int(rem2))' "$SCRIPT" || true)
if [[ "$residual" -ne 0 ]]; then
    echo "FAIL: residual min(5, int(rem2)) dispatch cap remains ($residual site(s))"
    fail=1
fi

# 4. script still parses
bash -n "$SCRIPT" || { echo "FAIL: syntax error in $SCRIPT"; exit 1; }

if [[ "$fail" -eq 0 ]]; then
    echo "PASS: resume dispatch timeout parity (both sites cap at 10s)"
else
    exit 1
fi
