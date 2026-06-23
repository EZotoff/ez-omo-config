#!/usr/bin/env bash
# DCP payload-budget patch verification.
# v3.1.13+: marker checks grep dist/index.js bundle; functional tests import
# TypeScript source via tsx (see payload-budget.mjs).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ -f "$SCRIPT_DIR/helpers.sh" ]]; then
    source "$SCRIPT_DIR/helpers.sh"
fi

HARNESS="$SCRIPT_DIR/dcp-local-patch/payload-budget.mjs"

# Marker pattern for byte-budget presence in patched files
MARKER_PATTERN='maxPayloadBytes|byte-budget|payload-budget|pruneByByteBudget|measureMessagePayloadBytes|BYTE_BUDGET_DEFAULTS'

# DCP roots — v3.1.13+ uses tsup bundling: runtime code is in dist/index.js
INSTALLED_BUNDLE="$HOME/.config/opencode/node_modules/@tarquinen/opencode-dcp/dist/index.js"
RUNTIME_BUNDLE="$HOME/.cache/opencode/node_modules/@tarquinen/opencode-dcp/dist/index.js"
PACKAGE_CACHE_LATEST_BUNDLE="$HOME/.cache/opencode/packages/@tarquinen/opencode-dcp@latest/node_modules/@tarquinen/opencode-dcp/dist/index.js"
PACKAGE_CACHE_PINNED_BUNDLE="$HOME/.cache/opencode/packages/@tarquinen/opencode-dcp@3.1.13/node_modules/@tarquinen/opencode-dcp/dist/index.js"
BUN_CACHE_BUNDLE_GLOB="$HOME/.bun/install/cache/@tarquinen/opencode-dcp@3.*@@@*/dist/index.js"

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
        echo "FAIL: $case_name (byte-budget markers missing in $file_path)"
    fi
}

run_marker_case "installed-reference-byte-budget"      "$INSTALLED_BUNDLE"              "required"
run_marker_case "installed-runtime-byte-budget"        "$RUNTIME_BUNDLE"                "required"
run_marker_case "installed-pkgcache-latest-byte-budget" "$PACKAGE_CACHE_LATEST_BUNDLE"   "required"
run_marker_case "installed-pkgcache-3.1.13-byte-budget"  "$PACKAGE_CACHE_PINNED_BUNDLE"   "required"

if [[ -n "$XDG_RUNTIME_BUNDLE" ]]; then
    run_marker_case "installed-xdg-runtime-byte-budget" "$XDG_RUNTIME_BUNDLE" "required"
fi
if [[ -n "$XDG_PACKAGE_CACHE_LATEST_BUNDLE" ]]; then
    run_marker_case "installed-xdg-pkgcache-latest-byte-budget" "$XDG_PACKAGE_CACHE_LATEST_BUNDLE" "required"
fi
if [[ -n "$XDG_PACKAGE_CACHE_PINNED_BUNDLE" ]]; then
    run_marker_case "installed-xdg-pkgcache-3.1.13-byte-budget" "$XDG_PACKAGE_CACHE_PINNED_BUNDLE" "required"
fi

for bun_cache_bundle in $BUN_CACHE_BUNDLE_GLOB; do
    if [[ -f "$bun_cache_bundle" ]]; then
        bun_cache_package="$(basename "$(dirname "$(dirname "$bun_cache_bundle")")")"
        run_marker_case "installed-bun-cache-$bun_cache_package-byte-budget" "$bun_cache_bundle" "required"
    fi
done

# ---------------------------------------------------------------------------
# Functional cases
# ---------------------------------------------------------------------------
run_case "below-budget-noop"
run_case "huge-tool-output-compacts"
run_case "repeated-scaffold-oldest-first"
run_case "repeated-provider-errors-oldest-first"
run_case "latest-todo-preserved"
run_case "compressed-placeholder-survives"
run_case "multibyte-cjk-emoji"
run_case "exact-threshold-and-one-byte-over"
run_case "protected-frontier-over-limit"

echo ""
echo "=========================================="
echo "DCP payload-budget: $TOTAL_PASSED passed, $TOTAL_FAILED failed"
echo "=========================================="

if [[ $TOTAL_FAILED -gt 0 ]]; then
    exit 1
fi

exit 0
