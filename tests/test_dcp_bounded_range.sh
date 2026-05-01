#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ -f "$SCRIPT_DIR/helpers.sh" ]]; then
    source "$SCRIPT_DIR/helpers.sh"
fi

HARNESS="$SCRIPT_DIR/dcp-local-patch/bounded-range.mjs"
MARKER_PATTERN='compress\.retentionMode|compress\.maxArchivedSummaryTokens|retentionMode|maxArchivedSummaryTokens'

REFERENCE_CONFIG_JS="$HOME/.config/opencode/node_modules/@tarquinen/opencode-dcp/dist/lib/config.js"
RUNTIME_CONFIG_JS="$HOME/.cache/opencode/node_modules/@tarquinen/opencode-dcp/dist/lib/config.js"
PACKAGE_CACHE_CONFIG_JS="$HOME/.cache/opencode/packages/@tarquinen/opencode-dcp@latest/node_modules/@tarquinen/opencode-dcp/dist/lib/config.js"

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

run_marker_case "markers-reference-copy" "$REFERENCE_CONFIG_JS" "required"
run_marker_case "markers-runtime-copy" "$RUNTIME_CONFIG_JS" "required"
run_marker_case "markers-package-cache-copy" "$PACKAGE_CACHE_CONFIG_JS" "required"

run_case "monotonic-summary-bound"
run_case "archived-raw-stays-out-of-prompt"
run_case "persisted-frontier-state"
run_case "decompress-archived-rejected"
run_case "bounded-runtime-proof-metadata"

echo ""
echo "=========================================="
echo "DCP bounded-range: $TOTAL_PASSED passed, $TOTAL_FAILED failed"
echo "=========================================="

if [[ $TOTAL_FAILED -gt 0 ]]; then
    exit 1
fi

exit 0
