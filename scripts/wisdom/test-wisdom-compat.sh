#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/knowledge-constants.sh" 2>/dev/null || { echo "ERROR: Failed to source knowledge-constants.sh" >&2; exit 1; }
source "${SCRIPT_DIR}/wisdom-common.sh" 2>/dev/null || { echo "ERROR: Failed to source wisdom-common.sh" >&2; exit 1; }

TEST_TAG="test-compat-v2"
TEST_PROJECT="test-project-compat-v2"
TEST_PLAN="test-plan-compat-v2"
EVIDENCE_FILE="${HOME}/.sisyphus/evidence/task-12-compat-matrix.txt"

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
    log_info "Cleaning up test data..."
    if [[ -f "${WISDOM_SYSTEM_DIR}" ]]; then
        local ids
        ids=$(jq -r "select(.tags[]? | contains(\"${TEST_TAG}\")) | .id" "${WISDOM_SYSTEM_DIR}" 2>/dev/null || true)
        for id in $ids; do
            [[ -n "$id" ]] && "${SCRIPT_DIR}/wisdom-delete.sh" --id "$id" --scope system --force >/dev/null 2>&1 || true
        done
    fi
    local project_file="${WISDOM_BASE_DIR}/projects/${TEST_PROJECT}.jsonl"
    if [[ -f "$project_file" ]]; then
        local ids
        ids=$(jq -r "select(.tags[]? | contains(\"${TEST_TAG}\")) | .id" "$project_file" 2>/dev/null || true)
        for id in $ids; do
            [[ -n "$id" ]] && "${SCRIPT_DIR}/wisdom-delete.sh" --id "$id" --scope project --project-id "${TEST_PROJECT}" --force >/dev/null 2>&1 || true
        done
        rm -f "$project_file" 2>/dev/null || true
    fi
    local plan_file="${WISDOM_BASE_DIR}/plans/${TEST_PLAN}.jsonl"
    if [[ -f "$plan_file" ]]; then
        local ids
        ids=$(jq -r "select(.tags[]? | contains(\"${TEST_TAG}\")) | .id" "$plan_file" 2>/dev/null || true)
        for id in $ids; do
            [[ -n "$id" ]] && "${SCRIPT_DIR}/wisdom-delete.sh" --id "$id" --scope plan --project-id "${TEST_PLAN}" --force >/dev/null 2>&1 || true
        done
        rm -f "$plan_file" 2>/dev/null || true
    fi
}

trap cleanup_test_data EXIT
mkdir -p "$(dirname "$EVIDENCE_FILE")"
{
    echo "Wisdom Canonical Contract Test Results"
    echo "========================================"
    echo "Started: $(date)"
    echo ""
} > "$EVIDENCE_FILE"

test_metadata_roundtrip() {
    local output entry_id entry_json
    output=$(echo "Metadata roundtrip test entry with sufficient length for wisdom validation rules" | \
        "${SCRIPT_DIR}/wisdom-write.sh" \
            --scope system --type fact --tags "${TEST_TAG},metadata-test" --score 5 \
            --authority verified --provenance manual --origin-session "test-session-123" \
            --verified-at "2025-01-15T10:30:00Z" --review-due "2027-07-15T10:30:00Z" 2>&1)
    entry_id=$(echo "$output" | grep -oE '[0-9]{8}-[0-9]{6}-[a-z0-9]{4}')
    [[ -z "$entry_id" ]] && { echo "Failed to extract entry ID"; return 1; }
    entry_json=$(jq -c --arg id "$entry_id" 'select(.id == $id)' "${WISDOM_SYSTEM_DIR}" 2>/dev/null)
    [[ -z "$entry_json" ]] && { echo "Entry not found"; return 1; }
    [[ $(echo "$entry_json" | jq -r '.authority')    == "verified" ]]        || { echo "authority mismatch"; return 1; }
    [[ $(echo "$entry_json" | jq -r '.status')      == "active" ]]          || { echo "status mismatch"; return 1; }
    [[ $(echo "$entry_json" | jq -r '.provenance')  == "manual" ]]          || { echo "provenance mismatch"; return 1; }
    [[ $(echo "$entry_json" | jq -r '.origin_session') == "test-session-123" ]] || { echo "origin_session mismatch"; return 1; }
    [[ $(echo "$entry_json" | jq -r '.verified_at') == "2025-01-15T10:30:00Z" ]] || { echo "verified_at mismatch"; return 1; }
    [[ $(echo "$entry_json" | jq -r '.review_due')  == "2027-07-15T10:30:00Z" ]] || { echo "review_due mismatch"; return 1; }
    return 0
}

test_search_excludes_inactive() {
    local active_id superseded_id retracted_id search_output
    active_id=$(echo "Active search test entry for default exclusion testing" | \
        "${SCRIPT_DIR}/wisdom-write.sh" --scope system --type fact --tags "${TEST_TAG},search-exclude" --score 5 2>&1 | grep -oE '[0-9]{8}-[0-9]{6}-[a-z0-9]{4}')
    [[ -z "$active_id" ]] && { echo "Failed to create active entry"; return 1; }
    superseded_id=$(echo "Superseded search test entry for default exclusion testing" | \
        "${SCRIPT_DIR}/wisdom-write.sh" --scope system --type fact --tags "${TEST_TAG},search-exclude" --score 5 2>&1 | grep -oE '[0-9]{8}-[0-9]{6}-[a-z0-9]{4}')
    [[ -z "$superseded_id" ]] && { echo "Failed to create superseded entry"; return 1; }
    retracted_id=$(echo "Retracted search test entry for default exclusion testing" | \
        "${SCRIPT_DIR}/wisdom-write.sh" --scope system --type fact --tags "${TEST_TAG},search-exclude" --score 5 2>&1 | grep -oE '[0-9]{8}-[0-9]{6}-[a-z0-9]{4}')
    [[ -z "$retracted_id" ]] && { echo "Failed to create retracted entry"; return 1; }
    "${SCRIPT_DIR}/wisdom-edit.sh" --id "$superseded_id" --scope system --set-status superseded --set-superseded-by "$active_id" >/dev/null 2>&1
    "${SCRIPT_DIR}/wisdom-edit.sh" --id "$retracted_id" --scope system --set-status retracted >/dev/null 2>&1
    search_output=$("${SCRIPT_DIR}/wisdom-search.sh" "default exclusion testing" --scope system --tags "${TEST_TAG},search-exclude" --json 2>/dev/null)
    local count
    count=$(echo "$search_output" | jq 'length')
    [[ "$count" -eq 1 ]] || { echo "Expected 1 result, got $count"; return 1; }
    local found_id
    found_id=$(echo "$search_output" | jq -r '.[0].id')
    [[ "$found_id" == "$active_id" ]] || { echo "Expected active entry, got $found_id"; return 1; }
    return 0
}

test_status_aware_ranking() {
    local stale_published_id active_verified_id search_output
    stale_published_id=$(echo "Stale published entry for ranking test with sufficient length" | \
        "${SCRIPT_DIR}/wisdom-write.sh" --scope system --type fact --tags "${TEST_TAG},rank-test" --score 5 \
        --authority published --status stale --verified-at "2025-01-01T00:00:00Z" 2>&1 | grep -oE '[0-9]{8}-[0-9]{6}-[a-z0-9]{4}')
    [[ -z "$stale_published_id" ]] && { echo "Failed to create stale published entry"; return 1; }
    active_verified_id=$(echo "Active verified entry for ranking test with sufficient length" | \
        "${SCRIPT_DIR}/wisdom-write.sh" --scope system --type fact --tags "${TEST_TAG},rank-test" --score 5 \
        --authority verified --status active --verified-at "2025-01-01T00:00:00Z" 2>&1 | grep -oE '[0-9]{8}-[0-9]{6}-[a-z0-9]{4}')
    [[ -z "$active_verified_id" ]] && { echo "Failed to create active verified entry"; return 1; }
    search_output=$("${SCRIPT_DIR}/wisdom-search.sh" "ranking test" --scope system --tags "${TEST_TAG},rank-test" --json 2>/dev/null)
    local first_id
    first_id=$(echo "$search_output" | jq -r '.[0].id')
    [[ "$first_id" == "$active_verified_id" ]] || { echo "Expected active+verified first, got $first_id"; return 1; }
    return 0
}

test_contradiction_unknown() {
    local id1 id2 result
    id1=$(echo "Always use approach X for handling contradictions in wisdom entries" | \
        "${SCRIPT_DIR}/wisdom-write.sh" --scope system --type decision --tags "${TEST_TAG},contradict-test" --score 5 2>&1 | grep -oE '[0-9]{8}-[0-9]{6}-[a-z0-9]{4}')
    [[ -z "$id1" ]] && { echo "Failed to create entry A"; return 1; }
    id2=$(echo "Never use approach X for handling contradictions in wisdom entries" | \
        "${SCRIPT_DIR}/wisdom-write.sh" --scope system --type decision --tags "${TEST_TAG},contradict-test" --score 5 2>&1 | grep -oE '[0-9]{8}-[0-9]{6}-[a-z0-9]{4}')
    [[ -z "$id2" ]] && { echo "Failed to create entry B"; return 1; }
    "${SCRIPT_DIR}/wisdom-edit.sh" --id "$id1" --scope system --set-contradicts "$id2" >/dev/null 2>&1
    local tmp
    tmp=$(mktemp)
    jq --arg id "$id1" 'if .id == $id then .title = "Approach X for contradictions" else . end' "${WISDOM_SYSTEM_DIR}" > "$tmp"
    mv "$tmp" "${WISDOM_SYSTEM_DIR}"
    tmp=$(mktemp)
    jq --arg id "$id2" 'if .id == $id then .title = "Approach X for contradictions" else . end' "${WISDOM_SYSTEM_DIR}" > "$tmp"
    mv "$tmp" "${WISDOM_SYSTEM_DIR}"
    local entry1 entry2
    entry1=$(jq -c --arg id "$id1" 'select(.id == $id)' "${WISDOM_SYSTEM_DIR}")
    entry2=$(jq -c --arg id "$id2" 'select(.id == $id)' "${WISDOM_SYSTEM_DIR}")
    result=$(wisdom_check_contradiction "$entry1" "$entry2")
    [[ "$result" == "UNKNOWN" ]] || { echo "Expected UNKNOWN, got: $result"; return 1; }
    return 0
}

test_concurrent_safety() {
    local i
    for i in $(seq 1 20); do
        "${SCRIPT_DIR}/wisdom-write.sh" --scope system --type fact --tags "${TEST_TAG},concurrent" \
            --content "Concurrent mutation safety test entry number $i with enough length" >/dev/null 2>&1 &
    done
    wait
    local count corrupted
    count=$(grep -c "Concurrent mutation safety test entry" "${WISDOM_SYSTEM_DIR}" 2>/dev/null || echo "0")
    corrupted=0
    while IFS= read -r line; do
        if echo "$line" | grep -q "${TEST_TAG},concurrent"; then
            if ! echo "$line" | jq . >/dev/null 2>&1; then
                corrupted=$((corrupted + 1))
            fi
        fi
    done < "${WISDOM_SYSTEM_DIR}"
    [[ $count -ge 20 && $corrupted -eq 0 ]] || { echo "Concurrent writes failed: $count entries, $corrupted corrupted"; return 1; }
    return 0
}

test_closeout_lifecycle() {
    local closeout_id
    closeout_id=$(echo "Closeout test entry about the importance of testing closeout behavior thoroughly" | \
        "${SCRIPT_DIR}/wisdom-closeout.sh" --scope system --tags "${TEST_TAG},closeout-test" 2>&1 | grep -oE '[0-9]{8}-[0-9]{6}-[a-z0-9]{4}')
    [[ -z "$closeout_id" ]] && { echo "Failed to create closeout entry"; return 1; }
    local entry_json
    entry_json=$(jq -c --arg id "$closeout_id" 'select(.id == $id)' "${WISDOM_SYSTEM_DIR}")
    [[ $(echo "$entry_json" | jq -r '.provenance') == "closeout" ]] || { echo "provenance != closeout"; return 1; }
    [[ $(echo "$entry_json" | jq -r '.authority') == "candidate" ]] || { echo "authority != candidate"; return 1; }
    [[ $(echo "$entry_json" | jq -r '.status') == "active" ]] || { echo "status != active"; return 1; }
    return 0
}

test_nomination_infra_only() {
    local nom_id rejected_output
    nom_id=$(echo "Nomination test entry about deployment infrastructure configuration details" | \
        "${SCRIPT_DIR}/wisdom-nominate.sh" --scope system --tags "${TEST_TAG},nomination-test,infra" 2>&1 | grep -oE '[0-9]{8}-[0-9]{6}-[a-z0-9]{4}')
    [[ -z "$nom_id" ]] && { echo "Failed to create nomination (system scope)"; return 1; }
    local entry_json
    entry_json=$(jq -c --arg id "$nom_id" 'select(.id == $id)' "${WISDOM_SYSTEM_DIR}")
    [[ $(echo "$entry_json" | jq -r '.provenance') == "nomination" ]] || { echo "provenance != nomination"; return 1; }
    rejected_output=$(echo "Nomination test entry about business logic" | \
        "${SCRIPT_DIR}/wisdom-nominate.sh" --scope project --project-id "${TEST_PROJECT}" --tags "${TEST_TAG},nomination-test" 2>&1 || true)
    if echo "$rejected_output" | grep -qi "rejected"; then :; else
        echo "Expected nomination rejection for non-infra project scope"
        return 1
    fi
    nom_id=$(echo "Nomination test entry about deployment config for the project" | \
        "${SCRIPT_DIR}/wisdom-nominate.sh" --scope project --project-id "${TEST_PROJECT}" --tags "${TEST_TAG},nomination-test,deployment" 2>&1 | grep -oE '[0-9]{8}-[0-9]{6}-[a-z0-9]{4}')
    [[ -n "$nom_id" ]] || { echo "Failed to create nomination (project scope with infra tag)"; return 1; }
    return 0
}

test_publish_behavior() {
    local entry_id publish_output
    entry_id=$(echo "Publish test entry about publishing wisdom artifacts correctly and thoroughly" | \
        "${SCRIPT_DIR}/wisdom-write.sh" --scope system --type pattern --tags "${TEST_TAG},publish-test" --score 5 \
        --authority verified --verified-at "2025-01-01T00:00:00Z" 2>&1 | grep -oE '[0-9]{8}-[0-9]{6}-[a-z0-9]{4}')
    [[ -z "$entry_id" ]] && { echo "Failed to create publish test entry"; return 1; }
    publish_output=$("${SCRIPT_DIR}/wisdom-publish.sh" --id "$entry_id" --reason "test publish" 2>&1)
    [[ $? -eq 0 ]] || { echo "Publish failed: $publish_output"; return 1; }
    local entry_json
    entry_json=$(jq -c --arg id "$entry_id" 'select(.id == $id)' "${WISDOM_SYSTEM_DIR}")
    [[ $(echo "$entry_json" | jq -r '.authority') == "published" ]] || { echo "authority != published after publish"; return 1; }
    [[ $(echo "$entry_json" | jq -r '.provenance') == "publish-export" ]] || { echo "provenance != publish-export after publish"; return 1; }
    local stale_id stale_publish_output
    stale_id=$(echo "Stale publish test entry that should not be publishable" | \
        "${SCRIPT_DIR}/wisdom-write.sh" --scope system --type fact --tags "${TEST_TAG},publish-test" --score 5 \
        --authority candidate --status stale 2>&1 | grep -oE '[0-9]{8}-[0-9]{6}-[a-z0-9]{4}')
    [[ -z "$stale_id" ]] && { echo "Failed to create stale entry"; return 1; }
    stale_publish_output=$("${SCRIPT_DIR}/wisdom-publish.sh" --id "$stale_id" --reason "test publish stale" 2>&1 || true)
    if echo "$stale_publish_output" | grep -qi "cannot publish\|stale\|error"; then :; else
        echo "Expected publish rejection for stale entry"
        return 1
    fi
    return 0
}

test_secret_filtering() {
    local blocked_output
    blocked_output=$(echo "API_KEY=sk-test1234567890abcdef1234567890abcdef" | \
        "${SCRIPT_DIR}/wisdom-write.sh" --scope system --type fact --tags "${TEST_TAG},secret-test" 2>&1 || true)
    if echo "$blocked_output" | grep -qi "secret\|blocked\|error"; then :; else
        echo "Expected secret blocking for API key"
        return 1
    fi
    blocked_output=$(echo "-----BEGIN RSA PRIVATE KEY-----\nMIIEpAIBAAKCAQEA..." | \
        "${SCRIPT_DIR}/wisdom-write.sh" --scope system --type fact --tags "${TEST_TAG},secret-test" 2>&1 || true)
    if echo "$blocked_output" | grep -qi "secret\|blocked\|error"; then :; else
        echo "Expected secret blocking for private key"
        return 1
    fi
    blocked_output=$(echo "aws_access_key_id = AKIAIOSFODNN7EXAMPLE" | \
        "${SCRIPT_DIR}/wisdom-closeout.sh" --scope system --tags "${TEST_TAG},secret-test" 2>&1 || true)
    if echo "$blocked_output" | grep -qi "secret\|blocked\|error"; then :; else
        echo "Expected secret blocking for AWS key in closeout"
        return 1
    fi
    return 0
}

test_real_fixtures() {
    local fixture_count
    fixture_count=$(wc -l < "${WISDOM_SYSTEM_DIR}" 2>/dev/null || echo "0")
    [[ "$fixture_count" -gt 0 ]] || { echo "No real fixtures found"; return 1; }
    local invalid
    invalid=0
    while IFS= read -r line; do
        if ! echo "$line" | jq empty >/dev/null 2>&1; then
            invalid=$((invalid + 1))
        fi
    done < "${WISDOM_SYSTEM_DIR}"
    [[ $invalid -eq 0 ]] || { echo "Found $invalid invalid JSON lines in real fixtures"; return 1; }
    local search_output
    search_output=$("${SCRIPT_DIR}/wisdom-search.sh" "pattern" --scope system --json --limit 5 2>/dev/null)
    [[ -n "$search_output" ]] || { echo "Search against real fixtures returned nothing"; return 1; }
    return 0
}

main() {
    log_info "=== Wisdom Canonical Contract Test Suite ==="
    log_info "Wisdom-first runtime — no manifest dependency"

    cleanup_test_data

    run_test "Metadata round-trip" test_metadata_roundtrip
    run_test "Search excludes superseded/retracted" test_search_excludes_inactive
    run_test "Status-aware ranking" test_status_aware_ranking
    run_test "Contradiction returns UNKNOWN" test_contradiction_unknown
    run_test "Concurrent mutation safety" test_concurrent_safety
    run_test "Closeout lifecycle" test_closeout_lifecycle
    run_test "Nomination infra-only" test_nomination_infra_only
    run_test "Publish behavior" test_publish_behavior
    run_test "Secret filtering" test_secret_filtering
    run_test "Real fixtures validation" test_real_fixtures

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
        log_error "Some tests failed. Check $EVIDENCE_FILE for details."
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
        log_success "All canonical contract tests passed!"
        return 0
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
