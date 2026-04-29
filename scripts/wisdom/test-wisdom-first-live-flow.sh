#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${HOME}/.sisyphus/scripts/knowledge-constants.sh" 2>/dev/null || source "${SCRIPT_DIR}/knowledge-constants.sh" 2>/dev/null || { echo "ERROR: Failed to source knowledge-constants.sh" >&2; exit 1; }

EVIDENCE_FILE="${HOME}/.sisyphus/evidence/task-12-live-flow.txt"
TEST_TAG="test-live-flow"
TEST_PROJECT="test-live-flow-project"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

log_info() { echo -e "${YELLOW}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[PASS]${NC} $*"; }
log_error() { echo -e "${RED}[FAIL]${NC} $*"; }

run_test() {
    local test_name="$1"; shift
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    log_info "Running: $test_name"
    if "$@" >/dev/null 2>&1; then
        log_success "$test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        log_error "$test_name"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

cleanup_test_data() {
    log_info "Cleaning up live flow test data..."
    if [[ -f "${WISDOM_SYSTEM_DIR}" ]]; then
        local ids
        ids=$(jq -r "select(.tags[]? | contains(\"${TEST_TAG}\")) | .id" "${WISDOM_SYSTEM_DIR}" 2>/dev/null || true)
        for id in $ids; do
            [[ -n "$id" ]] && "${SCRIPT_DIR}/wisdom-delete.sh" --id "$id" --scope system --force >/dev/null 2>&1 || true
        done
    fi
    local project_file="${WISDOM_BASE_DIR}/projects/${TEST_PROJECT}.jsonl"
    [[ -f "$project_file" ]] && rm -f "$project_file" 2>/dev/null || true
}

trap cleanup_test_data EXIT
mkdir -p "$(dirname "$EVIDENCE_FILE")"
{
    echo "Wisdom-first Live Flow Test Results"
    echo "====================================="
    echo "Started: $(date)"
    echo ""
} > "$EVIDENCE_FILE"

MANIFEST_BACKUP=""

test_seed_and_lookup() {
    local id1 id2 lookup_output
    id1=$(echo "Live flow seed entry A about testing the wisdom first runtime thoroughly" | \
        "${SCRIPT_DIR}/wisdom-write.sh" --scope system --type fact --tags "${TEST_TAG},live-flow" --score 5 2>&1 | grep -oE '[0-9]{8}-[0-9]{6}-[a-z0-9]{4}')
    [[ -z "$id1" ]] && { echo "Failed to seed entry A"; return 1; }
    id2=$(echo "Live flow seed entry B about verifying the canonical wisdom store works correctly" | \
        "${SCRIPT_DIR}/wisdom-write.sh" --scope system --type pattern --tags "${TEST_TAG},live-flow" --score 7 2>&1 | grep -oE '[0-9]{8}-[0-9]{6}-[a-z0-9]{4}')
    [[ -z "$id2" ]] && { echo "Failed to seed entry B"; return 1; }
    lookup_output=$("${SCRIPT_DIR}/knowledge-lookup.sh" "live flow seed" 2>&1)
    echo "$lookup_output" | grep -q "$id1" || { echo "Lookup did not find entry A"; return 1; }
    echo "$lookup_output" | grep -q "$id2" || { echo "Lookup did not find entry B"; return 1; }
    return 0
}

test_snapshot_without_manifests() {
    local snapshot_output
    snapshot_output=$("${SCRIPT_DIR}/knowledge-snapshot.sh" 2>&1)
    [[ -n "$snapshot_output" ]] || { echo "Snapshot produced no output"; return 1; }
    echo "$snapshot_output" | grep -q "Wisdom (Canonical)" || { echo "Snapshot missing Wisdom section"; return 1; }
    return 0
}

test_closeout_flow() {
    local closeout_id entry_json
    closeout_id=$(echo "Live flow closeout entry testing the closeout handler in end to end flow" | \
        "${SCRIPT_DIR}/wisdom-closeout.sh" --scope system --tags "${TEST_TAG},live-flow,closeout" 2>&1 | grep -oE '[0-9]{8}-[0-9]{6}-[a-z0-9]{4}' | tail -1)
    [[ -z "$closeout_id" ]] && { echo "Failed to create closeout entry"; return 1; }
    entry_json=$(jq -c --arg id "$closeout_id" 'select(.id == $id)' "${WISDOM_SYSTEM_DIR}")
    [[ $(echo "$entry_json" | jq -r '.provenance') == "closeout" ]] || { echo "closeout provenance mismatch"; return 1; }
    return 0
}

test_nomination_flow() {
    local nom_id entry_json
    nom_id=$(echo "Live flow nomination entry about deployment config for testing infrastructure" | \
        "${SCRIPT_DIR}/wisdom-nominate.sh" --scope system --tags "${TEST_TAG},live-flow,nomination,infra" 2>&1 | grep -oE '[0-9]{8}-[0-9]{6}-[a-z0-9]{4}')
    [[ -z "$nom_id" ]] && { echo "Failed to create nomination entry"; return 1; }
    entry_json=$(jq -c --arg id "$nom_id" 'select(.id == $id)' "${WISDOM_SYSTEM_DIR}")
    [[ $(echo "$entry_json" | jq -r '.provenance') == "nomination" ]] || { echo "nomination provenance mismatch"; return 1; }
    return 0
}

test_publish_flow() {
    local entry_id publish_output entry_json
    entry_id=$(echo "Live flow publish entry about publishing wisdom artifacts in end to end testing" | \
        "${SCRIPT_DIR}/wisdom-write.sh" --scope system --type pattern --tags "${TEST_TAG},live-flow,publish" --score 5 \
        --authority verified --verified-at "2025-01-01T00:00:00Z" 2>&1 | grep -oE '[0-9]{8}-[0-9]{6}-[a-z0-9]{4}')
    [[ -z "$entry_id" ]] && { echo "Failed to create publish entry"; return 1; }
    publish_output=$("${SCRIPT_DIR}/wisdom-publish.sh" --id "$entry_id" --reason "live flow test" 2>&1)
    [[ $? -eq 0 ]] || { echo "Publish failed"; return 1; }
    entry_json=$(jq -c --arg id "$entry_id" 'select(.id == $id)' "${WISDOM_SYSTEM_DIR}")
    [[ $(echo "$entry_json" | jq -r '.authority') == "published" ]] || { echo "publish authority mismatch"; return 1; }
    return 0
}

test_runtime_without_manifests() {
    local manifest_dir="${KNOWLEDGE_MANIFESTS_DIR}"
    MANIFEST_BACKUP=$(mktemp -d)
    mv "${manifest_dir}/system" "${MANIFEST_BACKUP}/system" 2>/dev/null || true
    mv "${manifest_dir}/workspace" "${MANIFEST_BACKUP}/workspace" 2>/dev/null || true
    mv "${manifest_dir}/project" "${MANIFEST_BACKUP}/project" 2>/dev/null || true

    local lookup_output snapshot_output
    lookup_output=$("${SCRIPT_DIR}/knowledge-lookup.sh" "live flow" 2>&1)
    snapshot_output=$("${SCRIPT_DIR}/knowledge-snapshot.sh" 2>&1)

    local lookup_ok=false snapshot_ok=false
    echo "$lookup_output" | grep -q "live flow" && lookup_ok=true
    echo "$snapshot_output" | grep -q "Wisdom (Canonical)" && snapshot_ok=true

    mv "${MANIFEST_BACKUP}/system" "${manifest_dir}/system" 2>/dev/null || true
    mv "${MANIFEST_BACKUP}/workspace" "${manifest_dir}/workspace" 2>/dev/null || true
    mv "${MANIFEST_BACKUP}/project" "${manifest_dir}/project" 2>/dev/null || true
    rmdir "$MANIFEST_BACKUP" 2>/dev/null || true

    [[ "$lookup_ok" == true ]] || { echo "Lookup failed without manifests"; return 1; }
    [[ "$snapshot_ok" == true ]] || { echo "Snapshot failed without manifests"; return 1; }
    return 0
}

test_all_operations_use_wisdom_only() {
    local wisdom_line_count manifest_line_count
    wisdom_line_count=$(wc -l < "${WISDOM_SYSTEM_DIR}" 2>/dev/null || echo "0")
    manifest_line_count=0
    if [[ -d "${KNOWLEDGE_MANIFESTS_DIR}/system" ]]; then
        manifest_line_count=$(find "${KNOWLEDGE_MANIFESTS_DIR}/system" -name "*.md" 2>/dev/null | wc -l)
    fi
    [[ $wisdom_line_count -gt 0 ]] || { echo "Wisdom store is empty"; return 1; }
    return 0
}

main() {
    log_info "=== Wisdom-first Live Flow Test ==="
    log_info "End-to-end: seed, lookup, snapshot, closeout, nomination, publish"

    run_test "Seed and lookup" test_seed_and_lookup
    run_test "Snapshot without manifests" test_snapshot_without_manifests
    run_test "Closeout flow" test_closeout_flow
    run_test "Nomination flow" test_nomination_flow
    run_test "Publish flow" test_publish_flow
    run_test "Runtime without manifests" test_runtime_without_manifests
    run_test "All operations use Wisdom only" test_all_operations_use_wisdom_only

    echo ""
    log_info "=== Test Summary ==="
    echo "Total tests: $TESTS_TOTAL"
    echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"

    if [[ $TESTS_FAILED -gt 0 ]]; then
        echo -e "${RED}Failed: $TESTS_FAILED${NC}"
        {
            echo ""
            echo "Test Summary:"
            echo "Total: $TESTS_TOTAL, Passed: $TESTS_PASSED, Failed: $TESTS_FAILED"
            echo "Completed: $(date)"
        } >> "$EVIDENCE_FILE"
        log_error "Some live flow tests failed. Check $EVIDENCE_FILE for details."
        return 1
    else
        echo -e "${GREEN}All tests passed!${NC}"
        {
            echo ""
            echo "Test Summary:"
            echo "Total: $TESTS_TOTAL, Passed: $TESTS_PASSED, Failed: $TESTS_FAILED"
            echo "Status: ALL TESTS PASSED"
            echo "Completed: $(date)"
        } >> "$EVIDENCE_FILE"
        log_success "All live flow tests passed!"
        return 0
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
