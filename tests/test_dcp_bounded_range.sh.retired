#!/usr/bin/env bash
# DCP bounded-range patch verification.
# Checks that patched files are present on disk across all three install copies
# (reference, runtime, package cache) and exercises five functional regression
# cases via the harness.
#
# LIMITATION: This test proves patch presence on disk. A long-running OpenCode
# server/TUI started BEFORE a patch sync may still use unpatched modules until
# restarted. To verify a fresh process does not emit unknown-key warnings, also
# run: bash tests/test_dcp_startup_warning.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ -f "$SCRIPT_DIR/helpers.sh" ]]; then
    source "$SCRIPT_DIR/helpers.sh"
fi

HARNESS="$SCRIPT_DIR/dcp-local-patch/bounded-range.mjs"
MARKER_PATTERN='compress\.retentionMode|compress\.maxArchivedSummaryTokens|retentionMode|maxArchivedSummaryTokens'

# v3.1.13+ uses tsup bundling: all runtime code is in dist/index.js (single bundle).
# Marker checks grep the bundle; functional tests import from source TS via tsx.
REFERENCE_BUNDLE="$HOME/.config/opencode/node_modules/@tarquinen/opencode-dcp/dist/index.js"
RUNTIME_BUNDLE="$HOME/.cache/opencode/node_modules/@tarquinen/opencode-dcp/dist/index.js"
PACKAGE_CACHE_LATEST_BUNDLE="$HOME/.cache/opencode/packages/@tarquinen/opencode-dcp@latest/node_modules/@tarquinen/opencode-dcp/dist/index.js"
PACKAGE_CACHE_PINNED_BUNDLE="$HOME/.cache/opencode/packages/@tarquinen/opencode-dcp@3.1.13/node_modules/@tarquinen/opencode-dcp/dist/index.js"
BUN_CACHE_BUNDLE_GLOB="$HOME/.bun/install/cache/@tarquinen/opencode-dcp@3.*@@@*/dist/index.js"

# XDG_CACHE_HOME cache roots (when set and differs from HOME/.cache)
XDG_RUNTIME_BUNDLE=""
XDG_PACKAGE_CACHE_LATEST_BUNDLE=""
XDG_PACKAGE_CACHE_PINNED_BUNDLE=""
if [[ -n "${XDG_CACHE_HOME:-}" && "${XDG_CACHE_HOME}" != "$HOME/.cache" ]]; then
    XDG_RUNTIME_BUNDLE="$XDG_CACHE_HOME/opencode/node_modules/@tarquinen/opencode-dcp/dist/index.js"
    XDG_PACKAGE_CACHE_LATEST_BUNDLE="$XDG_CACHE_HOME/opencode/packages/@tarquinen/opencode-dcp@latest/node_modules/@tarquinen/opencode-dcp/dist/index.js"
    XDG_PACKAGE_CACHE_PINNED_BUNDLE="$XDG_CACHE_HOME/opencode/packages/@tarquinen/opencode-dcp@3.1.13/node_modules/@tarquinen/opencode-dcp/dist/index.js"
fi

TOTAL_PASSED=0
TOTAL_FAILED=0

run_case() {
    local case_name="$1"
    echo "Running: $case_name"
    if npx tsx "$HARNESS" --case "$case_name"; then
        TOTAL_PASSED=$((TOTAL_PASSED + 1))
    else
        TOTAL_FAILED=$((TOTAL_FAILED + 1))
        echo "FAIL: $case_name"
    fi
}

run_marker_case() {
    local case_name="$1"
    local file_path="$2"
    local required_mode="$3"

    echo "Running: $case_name"

    if [[ ! -f "$file_path" ]]; then
        if [[ "$required_mode" == "required" ]]; then
            TOTAL_FAILED=$((TOTAL_FAILED + 1))
            echo "FAIL: $case_name (missing file: $file_path)"
        else
            echo "SKIP: $case_name (file not found: $file_path)"
        fi
        return
    fi

    if grep -Eq "$MARKER_PATTERN" "$file_path"; then
        TOTAL_PASSED=$((TOTAL_PASSED + 1))
    else
        TOTAL_FAILED=$((TOTAL_FAILED + 1))
        echo "FAIL: $case_name (bounded-retention markers missing in $file_path)"
    fi
}

run_marker_case "markers-reference-copy" "$REFERENCE_BUNDLE" "required"
run_marker_case "markers-runtime-copy" "$RUNTIME_BUNDLE" "required"
run_marker_case "markers-package-cache-latest" "$PACKAGE_CACHE_LATEST_BUNDLE" "required"
run_marker_case "markers-package-cache-pinned-3.1.13" "$PACKAGE_CACHE_PINNED_BUNDLE" "required"

if [[ -n "$XDG_RUNTIME_BUNDLE" ]]; then
    run_marker_case "markers-xdg-runtime-copy" "$XDG_RUNTIME_BUNDLE" "required"
fi
if [[ -n "$XDG_PACKAGE_CACHE_LATEST_BUNDLE" ]]; then
    run_marker_case "markers-xdg-package-cache-latest" "$XDG_PACKAGE_CACHE_LATEST_BUNDLE" "required"
fi
if [[ -n "$XDG_PACKAGE_CACHE_PINNED_BUNDLE" ]]; then
    run_marker_case "markers-xdg-package-cache-pinned-3.1.13" "$XDG_PACKAGE_CACHE_PINNED_BUNDLE" "required"
fi

for bun_cache_bundle in $BUN_CACHE_BUNDLE_GLOB; do
    if [[ -f "$bun_cache_bundle" ]]; then
        bun_cache_package="$(basename "$(dirname "$(dirname "$(dirname "$bun_cache_bundle")")")")"
        run_marker_case "markers-bun-cache-$bun_cache_package" "$bun_cache_bundle" "required"
    fi
done

run_case "monotonic-summary-bound"
run_case "archived-raw-stays-out-of-prompt"
run_case "persisted-frontier-state"
run_case "decompress-archived-rejected"
run_case "bounded-runtime-proof-metadata"

echo ""
echo "=========================================="
echo "DCP bounded-range: $TOTAL_PASSED passed, $TOTAL_FAILED failed"
echo "=========================================="
echo ""
echo "NOTE: File-marker checks prove patch presence on disk."
echo "      Run 'bash tests/test_dcp_startup_warning.sh' to verify a fresh"
echo "      OpenCode process does not emit unknown-key warnings."

if [[ $TOTAL_FAILED -gt 0 ]]; then
    exit 1
fi

exit 0
