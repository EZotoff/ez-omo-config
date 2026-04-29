#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/knowledge-constants.sh" 2>/dev/null || { echo "ERROR: Failed to source knowledge-constants.sh" >&2; exit 1; }

EVIDENCE_DIR="$HOME/.sisyphus/evidence"
mkdir -p "$EVIDENCE_DIR"
EVIDENCE_FILE="$EVIDENCE_DIR/task-12-contract-tests.txt"
TEST_TAG="test-contract-v2"

{
    echo "=== Knowledge Shim Contract Tests (Wisdom-first) ==="
    echo "Started: $(date)"
    echo ""
} > "$EVIDENCE_FILE"

log_result() {
    local ac="$1" status="$2" description="$3"
    echo "AC$ac: $status - $description" >> "$EVIDENCE_FILE"
    echo "AC$ac: $status - $description"
}

cleanup_test_data() {
    if [[ -f "$HOME/.sisyphus/wisdom/system.jsonl" ]]; then
        local ids
        ids=$(jq -r "select(.tags[]? | contains(\"${TEST_TAG}\")) | .id" "$HOME/.sisyphus/wisdom/system.jsonl" 2>/dev/null || true)
        for id in $ids; do
            [[ -n "$id" ]] && "${SCRIPT_DIR}/wisdom-delete.sh" --id "$id" --scope system --force >/dev/null 2>&1 || true
        done
    fi
}

cleanup_test_data

echo "Testing AC1: knowledge-lookup.sh delegates to Wisdom..."
echo "=== AC1 Test ===" >> "$EVIDENCE_FILE"

WISDOM_OUTPUT=$("$SCRIPT_DIR/wisdom-write.sh" --scope system --type fact --tags "${TEST_TAG},lookup-test" \
    --content "AC1 test wisdom entry for knowledge lookup shim delegation verification" 2>&1)
WISDOM_CREATED=$?
echo "$WISDOM_OUTPUT" >> "$EVIDENCE_FILE"

if [[ $WISDOM_CREATED -eq 0 ]]; then
    LOOKUP_OUTPUT=$("$SCRIPT_DIR/knowledge-lookup.sh" "AC1 test wisdom entry" 2>&1)
    echo "$LOOKUP_OUTPUT" >> "$EVIDENCE_FILE"
    if echo "$LOOKUP_OUTPUT" | grep -q "DEPRECATION" && echo "$LOOKUP_OUTPUT" | grep -q "AC1 test wisdom entry"; then
        log_result "1" "PASS" "knowledge-lookup.sh emits deprecation and returns wisdom results"
    else
        log_result "1" "FAIL" "knowledge-lookup.sh missing deprecation or wisdom results"
    fi
else
    log_result "1" "FAIL" "Failed to create test wisdom entry"
fi

echo "" >> "$EVIDENCE_FILE"

echo "Testing AC2: knowledge-snapshot.sh works without manifests..."
echo "=== AC2 Test ===" >> "$EVIDENCE_FILE"

SNAPSHOT_OUTPUT=$("$SCRIPT_DIR/knowledge-snapshot.sh" 2>&1)
echo "Snapshot output (first 200 chars): ${SNAPSHOT_OUTPUT:0:200}..." >> "$EVIDENCE_FILE"
CHARS=$(echo -n "$SNAPSHOT_OUTPUT" | wc -c)
echo "Character count: $CHARS" >> "$EVIDENCE_FILE"

if echo "$SNAPSHOT_OUTPUT" | grep -q "DEPRECATION" && [[ $CHARS -gt 0 ]]; then
    log_result "2" "PASS" "knowledge-snapshot.sh emits deprecation and produces output ($CHARS chars)"
else
    log_result "2" "FAIL" "knowledge-snapshot.sh missing deprecation or empty output"
fi

echo "" >> "$EVIDENCE_FILE"

echo "Testing AC3: knowledge-promote.sh delegates to wisdom-publish.sh..."
echo "=== AC3 Test ===" >> "$EVIDENCE_FILE"

PROMOTE_WISDOM_ID=$("$SCRIPT_DIR/wisdom-write.sh" --scope system --type pattern --tags "${TEST_TAG},promote-test" \
    --content "AC3 test wisdom entry for promotion shim delegation with enough length to pass validation" \
    --authority verified --verified-at "2025-01-01T00:00:00Z" 2>&1 | grep -oE '[0-9]{8}-[0-9]{6}-[a-z0-9]{4}')

if [[ -n "$PROMOTE_WISDOM_ID" ]]; then
    PROMOTE_OUTPUT=$("${SCRIPT_DIR}/../knowledge-promote.sh" --wisdom-id "$PROMOTE_WISDOM_ID" --type deployment --reason "test promotion" 2>&1)
    echo "$PROMOTE_OUTPUT" >> "$EVIDENCE_FILE"
    if echo "$PROMOTE_OUTPUT" | grep -qi "WARNING.*deprecated\|deprecated.*wisdom-publish" && \
       echo "$PROMOTE_OUTPUT" | grep -q "Publish Complete"; then
        log_result "3" "PASS" "knowledge-promote.sh emits deprecation warning and delegates to wisdom-publish.sh"
    else
        log_result "3" "FAIL" "knowledge-promote.sh did not delegate correctly"
    fi
else
    log_result "3" "FAIL" "Failed to create test wisdom entry for promotion"
fi

echo "" >> "$EVIDENCE_FILE"

echo "Testing AC4: Unknown topic returns UNKNOWN..."
echo "=== AC4 Test ===" >> "$EVIDENCE_FILE"

UNKNOWN_OUTPUT=$("$SCRIPT_DIR/knowledge-lookup.sh" "nonexistent-zzz-topic-xyz-12345" 2>&1 || true)
echo "$UNKNOWN_OUTPUT" >> "$EVIDENCE_FILE"

if echo "$UNKNOWN_OUTPUT" | grep -q "UNKNOWN" && echo "$UNKNOWN_OUTPUT" | grep -q "do NOT infer"; then
    log_result "4" "PASS" "Unknown topic correctly returns UNKNOWN with 'do NOT infer' warning"
else
    log_result "4" "FAIL" "Unknown topic response missing UNKNOWN or 'do NOT infer' warning"
fi

echo "" >> "$EVIDENCE_FILE"

echo "Testing AC5: All shims emit deprecation warnings..."
echo "=== AC5 Test ===" >> "$EVIDENCE_FILE"

LOOKUP_DEPRECATION=$("$SCRIPT_DIR/knowledge-lookup.sh" "test" 2>&1 || true)
SNAPSHOT_DEPRECATION=$("$SCRIPT_DIR/knowledge-snapshot.sh" 2>&1 || true)
PROMOTE_DEPRECATION=$("${SCRIPT_DIR}/../knowledge-promote.sh" --wisdom-id "fake" --type "fake" --reason "test" 2>&1 || true)

DEPRECATION_COUNT=0
if echo "$LOOKUP_DEPRECATION" | grep -qi "deprecat"; then DEPRECATION_COUNT=$((DEPRECATION_COUNT + 1)); fi
if echo "$SNAPSHOT_DEPRECATION" | grep -qi "deprecat"; then DEPRECATION_COUNT=$((DEPRECATION_COUNT + 1)); fi
if echo "$PROMOTE_DEPRECATION" | grep -qi "deprecat"; then DEPRECATION_COUNT=$((DEPRECATION_COUNT + 1)); fi

if [[ $DEPRECATION_COUNT -eq 3 ]]; then
    log_result "5" "PASS" "All 3 knowledge shims emit deprecation warnings"
else
    log_result "5" "FAIL" "Only $DEPRECATION_COUNT/3 shims emit deprecation warnings"
fi

echo "" >> "$EVIDENCE_FILE"

echo "Cleaning up test data..." >> "$EVIDENCE_FILE"
cleanup_test_data

echo "=== Final Verification ===" >> "$EVIDENCE_FILE"
echo "Test wisdom entries removed: $(if ! grep -q "${TEST_TAG}" "$HOME/.sisyphus/wisdom/system.jsonl" 2>/dev/null; then echo "YES"; else echo "NO"; fi)" >> "$EVIDENCE_FILE"

echo "" >> "$EVIDENCE_FILE"
echo "Completed: $(date)" >> "$EVIDENCE_FILE"

echo ""
echo "=== Test Summary ==="
grep "^AC[0-9]:" "$EVIDENCE_FILE"

PASS_COUNT=$(grep -c "AC[0-9]: PASS" "$EVIDENCE_FILE")
TOTAL_TESTS=$(grep -c "AC[0-9]:" "$EVIDENCE_FILE")

if [[ $PASS_COUNT -eq $TOTAL_TESTS ]]; then
    echo "All $TOTAL_TESTS tests passed!"
    exit 0
else
    echo "$PASS_COUNT/$TOTAL_TESTS tests passed"
    exit 1
fi
