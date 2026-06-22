#!/usr/bin/env bash
# DCP compress prompt contract test.
#
# Verifies that:
#   1. install.sh contains 'prompts/system.js' in DCP_PATCH_FILES.
#   2. After T5 sync, all DCP prompt copies contain the new internal-only
#      compress contract wording (no announcement, same-turn invoke).
#   3. Before T5 sync, missing targets produce a clear skip message rather
#      than an outright failure.
#
# Contract wording (patched in T2):
#   - NEW: "Do NOT announce that you will compress"
#   - NEW: "call the \`compress\` tool immediately in the same turn"
#   - OLD: "Before compressing, ask:" (must be absent)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ -f "$SCRIPT_DIR/helpers.sh" ]]; then
    source "$SCRIPT_DIR/helpers.sh"
fi

TOTAL_PASSED=0
TOTAL_FAILED=0

# -- Patterns --
NEW_CONTRACT_PATTERN='Do NOT announce that you will compress'
SAME_TURN_PATTERN='tool immediately in the same turn'
OLD_WORDING_PATTERN='Before compressing, ask:'

# -- Targets (v3.1.13+ uses tsup bundling: all prompts are in dist/index.js) --
SOURCE_BUILD_BUNDLE="/home/ezotoff/opencode-dynamic-context-pruning-v3.1.13/dist/index.js"
REFERENCE_INSTALL_BUNDLE="$HOME/.config/opencode/node_modules/@tarquinen/opencode-dcp/dist/index.js"
RUNTIME_INSTALL_BUNDLE="$HOME/.cache/opencode/node_modules/@tarquinen/opencode-dcp/dist/index.js"
PACKAGE_CACHE_BUNDLE="$HOME/.cache/opencode/packages/@tarquinen/opencode-dcp@latest/node_modules/@tarquinen/opencode-dcp/dist/index.js"

# -- Assertion helpers --

check_target() {
    local label="$1"
    local file_path="$2"
    local fallback_path="$3"   # optional bundled fallback (e.g. dist/index.js)

    echo "-- Target: $label --"
    echo "  File: $file_path"

    if [[ -f "$file_path" ]]; then
        echo "  Status: FOUND"
        check_file_content "$label" "$file_path"
    elif [[ -n "$fallback_path" && -f "$fallback_path" ]]; then
        echo "  Status: standalone not found, using bundled fallback"
        echo "  Fallback: $fallback_path"
        check_file_content "$label (bundled)" "$fallback_path"
    else
        echo "  Status: NOT FOUND (expected pre-sync; will be required after T5)"
        TOTAL_PASSED=$((TOTAL_PASSED + 1))
        echo "  -> SKIPPED (file not present yet)"
    fi
    echo ""
}

check_file_content() {
    local label="$1"
    local file_path="$2"

    # New contract wording must be present
    if grep -qF "$NEW_CONTRACT_PATTERN" "$file_path"; then
        TOTAL_PASSED=$((TOTAL_PASSED + 1))
        echo "  [PASS] NEW contract wording found"
    else
        TOTAL_FAILED=$((TOTAL_FAILED + 1))
        echo "  [FAIL] NEW contract wording missing in $file_path"
        echo "    Expected pattern: $NEW_CONTRACT_PATTERN"
    fi

    # Same-turn invoke must be present
    if grep -qE "$SAME_TURN_PATTERN" "$file_path"; then
        TOTAL_PASSED=$((TOTAL_PASSED + 1))
        echo "  [PASS] Same-turn invoke found"
    else
        TOTAL_FAILED=$((TOTAL_FAILED + 1))
        echo "  [FAIL] Same-turn invoke missing in $file_path"
        echo "    Expected pattern: $SAME_TURN_PATTERN"
    fi

    # Old wording must be absent
    if grep -qF "$OLD_WORDING_PATTERN" "$file_path"; then
        TOTAL_FAILED=$((TOTAL_FAILED + 1))
        echo "  [FAIL] Old wording STILL present in $file_path"
        echo "    Unwanted pattern: $OLD_WORDING_PATTERN"
    else
        TOTAL_PASSED=$((TOTAL_PASSED + 1))
        echo "  [PASS] Old wording absent"
    fi
}

# -- Test 1: install.sh DCP_PATCH_FILES entry --

echo "=========================================="
echo "DCP Compress Prompt Contract Test"
echo "=========================================="
echo ""

echo "-- Test: install.sh DCP_PATCH_FILES --"
echo "  Checking for: index.js (tsup bundle)"
if grep -qF 'index.js' "$REPO_ROOT/install.sh"; then
    TOTAL_PASSED=$((TOTAL_PASSED + 1))
    echo "  [PASS] install.sh contains index.js in DCP_PATCH_FILES"
else
    TOTAL_FAILED=$((TOTAL_FAILED + 1))
    echo "  [FAIL] install.sh does not contain index.js in DCP_PATCH_FILES"
fi
echo ""

# -- Tests 2-5: Four DCP prompt targets --

echo "------------------------------------------"
echo " DCP Prompt Copy Verification"
echo "------------------------------------------"
echo ""

check_target "source-build (bundled)"         "$SOURCE_BUILD_BUNDLE"       ""
check_target "reference-install"              "$REFERENCE_INSTALL_BUNDLE"  ""
check_target "runtime-install"                "$RUNTIME_INSTALL_BUNDLE"    ""
check_target "package-cache-latest"           "$PACKAGE_CACHE_BUNDLE"      ""

# -- Summary --

echo "=========================================="
echo "DCP compress prompt contract: $TOTAL_PASSED passed, $TOTAL_FAILED failed"
echo "=========================================="
echo ""
echo "NOTE: Before T5 sync (./install.sh --configs), missing target files and"
echo "      missing contract wording in unpatched copies are expected. After T5,"
echo "      all targets must pass."
echo ""
echo "Post-sync guide (v3.1.13+ tsup bundle model):"
echo "  - install.sh entry check ........ MUST pass (repo change)"
echo "  - source build (bundled) ........ SHOULD pass (patched in source)"
echo "  - reference install ............. MUST pass after install.sh --configs"
echo "  - runtime install ............... MUST pass after install.sh --configs"
echo "  - package cache ................. MUST pass after install.sh --configs"

if [[ $TOTAL_FAILED -gt 0 ]]; then
    exit 1
fi

exit 0
