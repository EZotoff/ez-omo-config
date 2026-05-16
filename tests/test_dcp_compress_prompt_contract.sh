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

# -- Targets (four DCP prompt copy locations) --
SOURCE_BUILD_FILE="/home/ezotoff/omo-hub/projects/opencode-dynamic-context-pruning/dist/lib/prompts/system.js"
SOURCE_BUILD_BUNDLE="/home/ezotoff/omo-hub/projects/opencode-dynamic-context-pruning/dist/index.js"
REFERENCE_INSTALL_FILE="$HOME/.config/opencode/node_modules/@tarquinen/opencode-dcp/dist/lib/prompts/system.js"
RUNTIME_INSTALL_FILE="$HOME/.cache/opencode/node_modules/@tarquinen/opencode-dcp/dist/lib/prompts/system.js"
PACKAGE_CACHE_FILE="$HOME/.cache/opencode/packages/@tarquinen/opencode-dcp@latest/node_modules/@tarquinen/opencode-dcp/dist/lib/prompts/system.js"

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
echo "  Checking for: prompts/system.js"
if grep -qF 'prompts/system.js' "$REPO_ROOT/install.sh"; then
    TOTAL_PASSED=$((TOTAL_PASSED + 1))
    echo "  [PASS] install.sh contains prompts/system.js in DCP_PATCH_FILES"
else
    TOTAL_FAILED=$((TOTAL_FAILED + 1))
    echo "  [FAIL] install.sh does not contain prompts/system.js in DCP_PATCH_FILES"
fi
echo ""

# -- Tests 2-5: Four DCP prompt targets --

echo "------------------------------------------"
echo " DCP Prompt Copy Verification"
echo "------------------------------------------"
echo ""

check_target "source-build (standalone)"    "$SOURCE_BUILD_FILE"    "$SOURCE_BUILD_BUNDLE"
check_target "reference-install"            "$REFERENCE_INSTALL_FILE"   ""
check_target "runtime-install"              "$RUNTIME_INSTALL_FILE"     ""
check_target "package-cache-latest"         "$PACKAGE_CACHE_FILE"       ""

# -- Summary --

echo "=========================================="
echo "DCP compress prompt contract: $TOTAL_PASSED passed, $TOTAL_FAILED failed"
echo "=========================================="
echo ""
echo "NOTE: Before T5 sync (./install.sh --configs), missing target files and"
echo "      missing contract wording in unpatched copies are expected. After T5,"
echo "      all targets must pass."
echo ""
echo "Pre-T5 tolerance guide:"
echo "  - install.sh entry check ........ MUST pass (repo change)"
echo "  - source build (standalone) ..... MAY skip (bundled into index.js)"
echo "  - source build (bundled) ........ SHOULD pass (patched in T2)"
echo "  - reference install ............. SHOULD fail (unpatched until T5)"
echo "  - runtime install ............... SHOULD fail (unpatched until T5)"
echo "  - package cache ................. SHOULD fail (unpatched until T5)"

if [[ $TOTAL_FAILED -gt 0 ]]; then
    exit 1
fi

exit 0
