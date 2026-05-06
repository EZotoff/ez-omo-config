#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HYGIENE_SCRIPT="$SCRIPT_DIR/../scripts/vera-hygiene.sh"

PASSED=0
FAILED=0

test_name() {
    printf 'TEST: %s\n' "$1"
}

pass() {
    printf '  PASS: %s\n' "$1"
    PASSED=$((PASSED + 1))
}

fail() {
    printf '  FAIL: %s\n' "$1" >&2
    FAILED=$((FAILED + 1))
}

# Setup a temp project directory with git init
setup_project() {
    local tmpdir
    tmpdir=$(mktemp -d)
    (
        cd "$tmpdir"
        git init -q
        git config user.email "test@example.com"
        git config user.name "Test User"
    )
    printf '%s\n' "$tmpdir"
}

# Cleanup temp project
cleanup_project() {
    local path="$1"
    rm -rf "$path"
}

run_hygiene() {
    bash "$HYGIENE_SCRIPT" "$@"
}

# ─── Tests ───────────────────────────────────────────────────────────

# 1. No existing .veraignore: apply creates one with managed block
test_no_existing_veraignore() {
    test_name "no existing .veraignore: apply creates one with managed block"
    local proj
    proj=$(setup_project)

    run_hygiene --project "$proj" --apply >/dev/null 2>&1

    if [[ -f "$proj/.veraignore" ]]; then
        if grep -q "BEGIN OMO VERA HYGIENE" "$proj/.veraignore"; then
            pass "managed block present in new .veraignore"
        else
            fail "managed block missing in new .veraignore"
        fi
    else
        fail ".veraignore not created"
    fi

    cleanup_project "$proj"
}

# 2. Existing user content is preserved
test_existing_user_content_preserved() {
    test_name "existing user content is preserved"
    local proj
    proj=$(setup_project)

    printf '%s\n' "src/vendor/" > "$proj/.veraignore"
    printf '%s\n' "*.tmp" >> "$proj/.veraignore"

    run_hygiene --project "$proj" --apply >/dev/null 2>&1

    if grep -q "src/vendor/" "$proj/.veraignore" && grep -q "\*.tmp" "$proj/.veraignore"; then
        pass "user content preserved"
    else
        fail "user content lost"
    fi

    if grep -q "BEGIN OMO VERA HYGIENE" "$proj/.veraignore"; then
        pass "managed block added alongside user content"
    else
        fail "managed block missing"
    fi

    cleanup_project "$proj"
}

# 3. Marker update idempotency: apply twice produces same result
test_marker_idempotency() {
    test_name "marker update idempotency: apply twice"
    local proj
    proj=$(setup_project)

    run_hygiene --project "$proj" --apply >/dev/null 2>&1
    local first
    first=$(cat "$proj/.veraignore")

    run_hygiene --project "$proj" --apply >/dev/null 2>&1
    local second
    second=$(cat "$proj/.veraignore")

    if [[ "$first" == "$second" ]]; then
        pass "second apply is idempotent"
    else
        fail "second apply changed the file"
    fi

    cleanup_project "$proj"
}

# 4. Unreadable directory detection
test_unreadable_dir_detection() {
    test_name "unreadable directory detection"
    local proj
    proj=$(setup_project)

    mkdir -p "$proj/data/nested"
    chmod 000 "$proj/data"

    local output
    output=$(run_hygiene --project "$proj" --check 2>&1) || true

    if echo "$output" | grep -q "data"; then
        pass "unreadable directory detected in output"
    else
        fail "unreadable directory not detected"
    fi

    chmod 755 "$proj/data"
    cleanup_project "$proj"
}

# 5. Tracked-file safety: do not ignore broad parent dirs with tracked files
test_tracked_file_safety() {
    test_name "tracked-file safety: do not ignore broad parent dirs"
    local proj
    proj=$(setup_project)

    mkdir -p "$proj/build"
    touch "$proj/build/main.js"
    touch "$proj/build/README.md"

    (
        cd "$proj"
        git add build/README.md
        git commit -q -m "add readme"
    )

    run_hygiene --project "$proj" --apply >/dev/null 2>&1

    if grep -q "SKIPPED (tracked files underneath): build/" "$proj/.veraignore"; then
        pass "build/ skipped because tracked files exist underneath"
    elif grep -q "^build/$" "$proj/.veraignore"; then
        fail "build/ incorrectly added despite tracked files underneath"
    else
        # build/ might not be present at all if no generated dirs detected
        pass "build/ not blindly added"
    fi

    cleanup_project "$proj"
}

# 6. Include fallback: verify #include .gitignore is NOT used
test_include_fallback() {
    test_name "include fallback: #include .gitignore not used"
    local proj
    proj=$(setup_project)

    run_hygiene --project "$proj" --apply >/dev/null 2>&1

    if grep -q "^#include .gitignore$" "$proj/.veraignore"; then
        fail "#include .gitignore is present (should not be until proven)"
    else
        pass "#include .gitignore absent; fallback comment present"
    fi

    if grep -q "Vera support" "$proj/.veraignore"; then
        pass "fallback explanation comment present"
    else
        fail "fallback explanation comment missing"
    fi

    cleanup_project "$proj"
}

# 7. Heavy dir detection: node_modules/
test_heavy_dir_detection() {
    test_name "heavy dir detection: node_modules/"
    local proj
    proj=$(setup_project)

    mkdir -p "$proj/node_modules/lodash"
    touch "$proj/node_modules/lodash/index.js"

    run_hygiene --project "$proj" --apply >/dev/null 2>&1

    if grep -q "^node_modules/$" "$proj/.veraignore"; then
        pass "node_modules/ added to .veraignore"
    else
        fail "node_modules/ not added to .veraignore"
    fi

    cleanup_project "$proj"
}

# 8. --check exits non-zero when blockers exist
test_check_exit_code() {
    test_name "--check exits non-zero when blockers exist"
    local proj
    proj=$(setup_project)

    mkdir -p "$proj/node_modules/lodash"

    local exit_code=0
    run_hygiene --project "$proj" --check >/dev/null 2>&1 || exit_code=$?

    if [[ "$exit_code" -eq 2 ]]; then
        pass "--check exits 2 when blockers exist"
    else
        fail "--check exited $exit_code instead of 2"
    fi

    cleanup_project "$proj"
}

# 9. --check exits 0 when no blockers
test_check_no_blockers() {
    test_name "--check exits 0 when no blockers"
    local proj
    proj=$(setup_project)

    local exit_code=0
    run_hygiene --project "$proj" --check >/dev/null 2>&1 || exit_code=$?

    if [[ "$exit_code" -eq 0 ]]; then
        pass "--check exits 0 when no blockers"
    else
        fail "--check exited $exit_code instead of 0"
    fi

    cleanup_project "$proj"
}

# 10. Invalid project path fails
test_invalid_project() {
    test_name "invalid project path fails"
    local exit_code=0
    run_hygiene --project /nonexistent/path --check 2>/dev/null || exit_code=$?

    if [[ "$exit_code" -ne 0 ]]; then
        pass "invalid project path causes non-zero exit"
    else
        fail "invalid project path did not fail"
    fi
}

# 11. Relative path is rejected
test_relative_path_rejected() {
    test_name "relative project path is rejected"
    local exit_code=0
    run_hygiene --project ./relative/path --check 2>/dev/null || exit_code=$?

    if [[ "$exit_code" -ne 0 ]]; then
        pass "relative path causes non-zero exit"
    else
        fail "relative path was accepted"
    fi
}

# 12. Non-git directory is rejected
test_non_git_rejected() {
    test_name "non-git directory is rejected"
    local tmpdir
    tmpdir=$(mktemp -d)

    local exit_code=0
    run_hygiene --project "$tmpdir" --check 2>/dev/null || exit_code=$?

    if [[ "$exit_code" -ne 0 ]]; then
        pass "non-git directory causes non-zero exit"
    else
        fail "non-git directory was accepted"
    fi

    rm -rf "$tmpdir"
}

# 13. .vera/ is always included
test_vera_always_included() {
    test_name ".vera/ is always included in managed block"
    local proj
    proj=$(setup_project)

    run_hygiene --project "$proj" --apply >/dev/null 2>&1

    if grep -q "^\.vera/$" "$proj/.veraignore"; then
        pass ".vera/ present in managed block"
    else
        fail ".vera/ missing from managed block"
    fi

    cleanup_project "$proj"
}

# ─── Main ────────────────────────────────────────────────────────────

echo "==================================="
echo " vera-hygiene.sh test suite"
echo "==================================="
echo ""

test_no_existing_veraignore
test_existing_user_content_preserved
test_marker_idempotency
test_unreadable_dir_detection
test_tracked_file_safety
test_include_fallback
test_heavy_dir_detection
test_check_exit_code
test_check_no_blockers
test_invalid_project
test_relative_path_rejected
test_non_git_rejected
test_vera_always_included

echo ""
echo "==================================="
printf 'Results: %d passed, %d failed\n' "$PASSED" "$FAILED"
echo "==================================="

[[ "$FAILED" -eq 0 ]]
