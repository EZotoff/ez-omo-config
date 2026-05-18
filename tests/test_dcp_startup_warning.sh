#!/usr/bin/env bash
# Regression test: fresh OpenCode startup must NOT emit DCP unknown-key warnings.
# Probes a non-interactive opencode serve startup, captures logs, and fails if
# bounded-retention config keys are rejected as unknown.
#
# IMPORTANT: This test proves the *fresh-start* behavior. A long-running OpenCode
# server/TUI that was started BEFORE a DCP patch sync may still emit the warning
# until it is restarted, because the patched modules are only loaded at startup.
# File-marker checks (test_dcp_bounded_range.sh) prove patch presence on disk;
# this test proves a fresh process does not warn.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

OPENCODE_BIN="${OPENCODE_BIN:-/home/ezotoff/.opencode/bin/opencode}"
TIMEOUT_SECS="${TIMEOUT_SECS:-8}"

# Early executable check: fail fast if the binary does not exist or is not executable.
if [[ ! -x "$OPENCODE_BIN" ]]; then
    echo "FAIL: OPENCODE_BIN not found or not executable: $OPENCODE_BIN"
    exit 1
fi

# Forbidden warning patterns
FORBIDDEN_PATTERN='Unknown keys: compress\.retentionMode, compress\.maxArchivedSummaryTokens|Unknown keys: compress\.maxPayloadBytes|DCP: config warning'
MARKER_PATTERN='compress\.retentionMode|compress\.maxArchivedSummaryTokens|compress\.maxPayloadBytes|retentionMode|maxArchivedSummaryTokens|maxPayloadBytes'

# File-marker check for the version-pinned @3.1.9 cache copy.
# This proves the patch files exist on disk even though the serve probe below
# cannot prove TUI toast suppression (warnings are emitted via ctx.client.tui.showToast()).
PINNED_PKG_CACHE_CONFIG="$HOME/.cache/opencode/packages/@tarquinen/opencode-dcp@3.1.9/node_modules/@tarquinen/opencode-dcp/dist/lib/config.js"
BUN_CACHE_CONFIG_GLOB="$HOME/.bun/install/cache/@tarquinen/opencode-dcp@3.*@@@*/dist/lib/config.js"
XDG_PINNED_PKG_CACHE_CONFIG=""
if [[ -n "${XDG_CACHE_HOME:-}" && "${XDG_CACHE_HOME}" != "$HOME/.cache" ]]; then
    XDG_PINNED_PKG_CACHE_CONFIG="$XDG_CACHE_HOME/opencode/packages/@tarquinen/opencode-dcp@3.1.9/node_modules/@tarquinen/opencode-dcp/dist/lib/config.js"
fi

echo "Checking version-pinned @3.1.9 cache copy for bounded-retention markers..."
if [[ -f "$PINNED_PKG_CACHE_CONFIG" ]]; then
    if grep -Eq "$MARKER_PATTERN" "$PINNED_PKG_CACHE_CONFIG"; then
        echo "PASS: markers present in @3.1.9 cache copy"
    else
        echo "FAIL: markers missing in @3.1.9 cache copy ($PINNED_PKG_CACHE_CONFIG)"
        exit 1
    fi
else
    echo "FAIL: @3.1.9 cache copy not found ($PINNED_PKG_CACHE_CONFIG)"
    exit 1
fi

if [[ -n "$XDG_PINNED_PKG_CACHE_CONFIG" ]]; then
    echo "Checking XDG version-pinned @3.1.9 cache copy for bounded-retention markers..."
    if [[ -f "$XDG_PINNED_PKG_CACHE_CONFIG" ]]; then
        if grep -Eq "$MARKER_PATTERN" "$XDG_PINNED_PKG_CACHE_CONFIG"; then
            echo "PASS: markers present in XDG @3.1.9 cache copy"
        else
            echo "FAIL: markers missing in XDG @3.1.9 cache copy ($XDG_PINNED_PKG_CACHE_CONFIG)"
            exit 1
        fi
    else
        echo "FAIL: XDG @3.1.9 cache copy not found ($XDG_PINNED_PKG_CACHE_CONFIG)"
        exit 1
    fi
fi

echo "Checking Bun DCP v3 cache copies for local config markers..."
BUN_CACHE_CHECKED=0
for bun_cache_config in $BUN_CACHE_CONFIG_GLOB; do
    if [[ -f "$bun_cache_config" ]]; then
        BUN_CACHE_CHECKED=$((BUN_CACHE_CHECKED + 1))
        if grep -Eq "$MARKER_PATTERN" "$bun_cache_config"; then
            echo "PASS: markers present in Bun cache copy: $bun_cache_config"
        else
            echo "FAIL: markers missing in Bun cache copy: $bun_cache_config"
            exit 1
        fi
    fi
done
if [[ $BUN_CACHE_CHECKED -eq 0 ]]; then
    echo "SKIP: no Bun DCP v3 cache copies found"
fi
echo ""

TMPLOG=$(mktemp)
trap 'rm -f "$TMPLOG"' EXIT

echo "Probing fresh OpenCode startup for DCP warnings..."
echo "  binary: $OPENCODE_BIN"
echo "  timeout: ${TIMEOUT_SECS}s"
echo ""

# Run opencode serve under timeout; capture both stdout and stderr.
# We expect timeout to kill the server after TIMEOUT_SECS (exit 124).
timeout "$TIMEOUT_SECS" "$OPENCODE_BIN" serve \
  --print-logs \
  --log-level WARN \
  --port 0 \
  >"$TMPLOG" 2>&1 &
CMD_PID=$!

# Wait up to TIMEOUT_SECS for the server to emit its listening line.
STARTED_OK=false
for _ in $(seq 1 "$TIMEOUT_SECS"); do
    if grep -q "opencode server listening on" "$TMPLOG" 2>/dev/null; then
        STARTED_OK=true
        break
    fi
    if ! kill -0 $CMD_PID 2>/dev/null; then
        # Process exited before we saw the listening line
        break
    fi
    sleep 1
done

# Capture the backgrounded process exit status FIRST, before any cleanup.
# We use `wait` with the PID to get the actual exit code of the timeout command.
# If the process is already dead, wait returns immediately with its exit code.
# If still alive, wait blocks until it exits (timeout will kill it).
EXIT_CODE=0
wait $CMD_PID 2>/dev/null
EXIT_CODE=$?

# Cleanup: if the process is somehow still alive (shouldn't happen after wait),
# terminate it and suppress expected signal-exit statuses.
if kill -0 $CMD_PID 2>/dev/null; then
    kill $CMD_PID 2>/dev/null
    wait $CMD_PID 2>/dev/null || true
fi

# timeout returns 124 when it kills the command; 125+ or other codes indicate
# timeout/internal errors. If the process died on its own, EXIT_CODE is the
# process's code.

# Determine if the startup itself looks healthy.
STARTUP_FAILED=false
if [[ "$STARTED_OK" != "true" ]]; then
    # Didn't see the listening line — check if the process crashed or exited early.
    # Exit code 124 means timeout killed it, which is expected even if we didn't
    # catch the line due to timing, but ONLY if there's some output.
    if [[ $EXIT_CODE -ne 124 ]] && [[ $EXIT_CODE -ne 0 ]]; then
        STARTUP_FAILED=true
    fi
    # If exit code is 124 but log is completely empty, that's also suspicious.
    if [[ $EXIT_CODE -eq 124 ]] && [[ ! -s "$TMPLOG" ]]; then
        STARTUP_FAILED=true
    fi
fi

echo "--- captured startup output ---"
cat "$TMPLOG"
echo "--- end of output ---"
echo ""

TOTAL_PASSED=0
TOTAL_FAILED=0

TOTAL_PASSED=$((TOTAL_PASSED + 1))

# Case 1: startup succeeded (or timed out as expected)
if [[ "$STARTUP_FAILED" == "true" ]]; then
    echo "FAIL: startup probe (server crashed or exited unexpectedly, exit code $EXIT_CODE)"
    TOTAL_FAILED=$((TOTAL_FAILED + 1))
else
    echo "PASS: startup probe (server started or timed out as expected)"
    TOTAL_PASSED=$((TOTAL_PASSED + 1))
fi

# Case 2: no DCP unknown-key warning
if grep -Eq "$FORBIDDEN_PATTERN" "$TMPLOG"; then
    echo "FAIL: DCP unknown-key warning detected in startup logs"
    grep -nE "$FORBIDDEN_PATTERN" "$TMPLOG" | while read -r line; do
        echo "  $line"
    done
    TOTAL_FAILED=$((TOTAL_FAILED + 1))
else
    echo "PASS: no DCP unknown-key warning in startup logs"
    TOTAL_PASSED=$((TOTAL_PASSED + 1))
fi

echo ""
echo "=========================================="
echo "DCP startup warning: $TOTAL_PASSED passed, $TOTAL_FAILED failed"
echo "=========================================="

if [[ $TOTAL_FAILED -gt 0 ]]; then
    exit 1
fi

exit 0
