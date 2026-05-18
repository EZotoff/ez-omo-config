#!/usr/bin/env bash
# DCP payload-budget patch verification.
# Supports two modes:
#   --source-dist : import DCP build output from source repo dist/lib
#   --installed   : import installed reference/runtime modules
#
# LIMITATION: --installed mode requires T5 sync (patch files copied to
# reference, runtime, and package-cache copies). In T4, only --source-dist
# is expected to pass.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ -f "$SCRIPT_DIR/helpers.sh" ]]; then
    source "$SCRIPT_DIR/helpers.sh"
fi

HARNESS="$SCRIPT_DIR/dcp-local-patch/payload-budget.mjs"

# Marker pattern for byte-budget presence in patched files
MARKER_PATTERN='maxPayloadBytes|byte-budget|payload-budget|pruneByByteBudget|measureMessagePayloadBytes|BYTE_BUDGET_DEFAULTS'

# DCP roots
SOURCE_DIST_ROOT="/home/ezotoff/omo-hub/projects/opencode-dynamic-context-pruning/dist/lib"
INSTALLED_ROOT="$HOME/.config/opencode/node_modules/@tarquinen/opencode-dcp/dist/lib"
RUNTIME_ROOT="$HOME/.cache/opencode/node_modules/@tarquinen/opencode-dcp/dist/lib"
PACKAGE_CACHE_LATEST_ROOT="$HOME/.cache/opencode/packages/@tarquinen/opencode-dcp@latest/node_modules/@tarquinen/opencode-dcp/dist/lib"
PACKAGE_CACHE_PINNED_ROOT="$HOME/.cache/opencode/packages/@tarquinen/opencode-dcp@3.1.9/node_modules/@tarquinen/opencode-dcp/dist/lib"
BUN_CACHE_ROOT_GLOB="$HOME/.bun/install/cache/@tarquinen/opencode-dcp@3.*@@@*/dist/lib"

XDG_RUNTIME_ROOT=""
XDG_PACKAGE_CACHE_LATEST_ROOT=""
XDG_PACKAGE_CACHE_PINNED_ROOT=""
if [[ -n "${XDG_CACHE_HOME:-}" && "${XDG_CACHE_HOME}" != "$HOME/.cache" ]]; then
    XDG_RUNTIME_ROOT="$XDG_CACHE_HOME/opencode/node_modules/@tarquinen/opencode-dcp/dist/lib"
    XDG_PACKAGE_CACHE_LATEST_ROOT="$XDG_CACHE_HOME/opencode/packages/@tarquinen/opencode-dcp@latest/node_modules/@tarquinen/opencode-dcp/dist/lib"
    XDG_PACKAGE_CACHE_PINNED_ROOT="$XDG_CACHE_HOME/opencode/packages/@tarquinen/opencode-dcp@3.1.9/node_modules/@tarquinen/opencode-dcp/dist/lib"
fi

MODE="installed"
TOTAL_PASSED=0
TOTAL_FAILED=0

# Parse mode flag
for arg in "$@"; do
    case "$arg" in
        --source-dist)
            MODE="source-dist"
            ;;
        --installed)
            MODE="installed"
            ;;
    esac
done

run_case() {
    local case_name="$1"
    echo "Running: $case_name (mode=$MODE)"
    if npx tsx "$HARNESS" --mode "$MODE" --case "$case_name"; then
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

# ---------------------------------------------------------------------------
# Source-dist file presence checks (prove build artifacts exist)
# ---------------------------------------------------------------------------
if [[ "$MODE" == "source-dist" ]]; then
    run_marker_case "source-dist-byte-budget-js"       "$SOURCE_DIST_ROOT/messages/byte-budget.js"       "required"
    run_marker_case "source-dist-byte-budget-dts"      "$SOURCE_DIST_ROOT/messages/byte-budget.d.ts"     "required"
    run_marker_case "source-dist-hooks-js"             "$SOURCE_DIST_ROOT/hooks.js"                      "required"
    # hooks.d.ts is a type declaration file; verify it exists without requiring runtime markers
    if [[ ! -f "$SOURCE_DIST_ROOT/hooks.d.ts" ]]; then
        TOTAL_FAILED=$((TOTAL_FAILED + 1))
        echo "FAIL: source-dist-hooks-dts (missing file: $SOURCE_DIST_ROOT/hooks.d.ts)"
    else
        TOTAL_PASSED=$((TOTAL_PASSED + 1))
        echo "PASS source-dist-hooks-dts"
    fi
    run_marker_case "source-dist-config-js"            "$SOURCE_DIST_ROOT/config.js"                     "required"
    run_marker_case "source-dist-config-dts"           "$SOURCE_DIST_ROOT/config.d.ts"                   "required"
fi

# ---------------------------------------------------------------------------
# Installed copy marker checks (prove patch presence on disk)
# ---------------------------------------------------------------------------
if [[ "$MODE" == "installed" ]]; then
    run_marker_case "installed-reference-byte-budget"      "$INSTALLED_ROOT/messages/byte-budget.js"              "required"
    run_marker_case "installed-runtime-byte-budget"        "$RUNTIME_ROOT/messages/byte-budget.js"                "required"
    run_marker_case "installed-pkgcache-latest-byte-budget" "$PACKAGE_CACHE_LATEST_ROOT/messages/byte-budget.js"   "required"
    run_marker_case "installed-pkgcache-3.1.9-byte-budget"  "$PACKAGE_CACHE_PINNED_ROOT/messages/byte-budget.js"   "required"

    if [[ -n "$XDG_RUNTIME_ROOT" ]]; then
        run_marker_case "installed-xdg-runtime-byte-budget" "$XDG_RUNTIME_ROOT/messages/byte-budget.js" "required"
    fi
    if [[ -n "$XDG_PACKAGE_CACHE_LATEST_ROOT" ]]; then
        run_marker_case "installed-xdg-pkgcache-latest-byte-budget" "$XDG_PACKAGE_CACHE_LATEST_ROOT/messages/byte-budget.js" "required"
    fi
    if [[ -n "$XDG_PACKAGE_CACHE_PINNED_ROOT" ]]; then
        run_marker_case "installed-xdg-pkgcache-3.1.9-byte-budget" "$XDG_PACKAGE_CACHE_PINNED_ROOT/messages/byte-budget.js" "required"
    fi

    for bun_cache_root in $BUN_CACHE_ROOT_GLOB; do
        if [[ -d "$bun_cache_root" ]]; then
            bun_cache_package="$(basename "$(dirname "$(dirname "$bun_cache_root")")")"
            run_marker_case "installed-bun-cache-$bun_cache_package-byte-budget" "$bun_cache_root/messages/byte-budget.js" "required"
        fi
    done
fi

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
echo "DCP payload-budget ($MODE): $TOTAL_PASSED passed, $TOTAL_FAILED failed"
echo "=========================================="

if [[ $TOTAL_FAILED -gt 0 ]]; then
    exit 1
fi

exit 0
