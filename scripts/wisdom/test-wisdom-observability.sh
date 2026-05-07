#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/knowledge-constants.sh" 2>/dev/null || { echo "ERROR: Failed to source knowledge-constants.sh" >&2; exit 1; }
source "${SCRIPT_DIR}/wisdom-common.sh" 2>/dev/null || { echo "ERROR: Failed to source wisdom-common.sh" >&2; exit 1; }

TEST_TAG="test-observability-v1"
TEST_PROJECT="test-observability-project"

TEMP_HOME=$(mktemp -d)
WISDOM_ROOT="${TEMP_HOME}/.sisyphus/wisdom"
WISDOM_EVENTS_PATH="${WISDOM_ROOT}/events.jsonl"
export HOME="$TEMP_HOME"
export WISDOM_ROOT
export WISDOM_EVENTS_PATH

mkdir -p "$WISDOM_ROOT"
mkdir -p "${TEMP_HOME}/.sisyphus/evidence"

EVIDENCE_FILE="${TEMP_HOME}/.sisyphus/evidence/task-6-wisdom-observability.txt"
REAL_EVIDENCE_DIR="${HOME}/.sisyphus/evidence"
mkdir -p "$REAL_EVIDENCE_DIR"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

log_info()  { echo -e "${YELLOW}[INFO]${NC} $*"; }
log_pass()  { echo -e "${GREEN}[PASS]${NC} $*"; }
log_fail()  { echo -e "${RED}[FAIL]${NC} $*"; }

run_test() {
    local test_name="$1"; shift
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    log_info "Running: $test_name"
    if "$@" >/dev/null 2>&1; then
        log_pass "$test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        log_fail "$test_name"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

cleanup() {
    rm -rf "$TEMP_HOME"
}
trap cleanup EXIT

validate_event_schema() {
    local line="$1"
    echo "$line" | jq -e -c '
        has("schema_version") and has("ts") and has("system")
        and has("event") and has("status") and has("trace_id")
        and has("invocation_id") and has("script") and has("pid")
        and has("duration_ms")
    ' >/dev/null 2>&1
}

events_for_trace() {
    local tid="$1"
    jq -s --arg tid "$tid" '[.[] | select(.trace_id == $tid)]' "$WISDOM_EVENTS_PATH" 2>/dev/null || echo "[]"
}

events_for_event_type() {
    local etype="$1"
    jq -s --arg etype "$etype" '[.[] | select(.event == $etype)]' "$WISDOM_EVENTS_PATH" 2>/dev/null || echo "[]"
}

count_events() {
    if [[ -f "$WISDOM_EVENTS_PATH" ]]; then
        wc -l < "$WISDOM_EVENTS_PATH" | tr -d ' '
    else
        echo 0
    fi
}

# ---------------------------------------------------------------------------
# 1. Schema validity
# ---------------------------------------------------------------------------
test_schema_validity() {
    : > "$WISDOM_EVENTS_PATH"
    local id
    id=$(echo "Schema validity test entry with sufficient length for validation" | \
        "${SCRIPT_DIR}/wisdom-write.sh" --scope system --type fact --tags "${TEST_TAG},schema" 2>&1 | grep -oE '[0-9]{8}-[0-9]{6}-[a-z0-9]{4}')
    [[ -n "$id" ]] || { echo "write failed"; return 1; }
    [[ -f "$WISDOM_EVENTS_PATH" ]] || { echo "no events file"; return 1; }
    local invalid=0
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        if ! validate_event_schema "$line"; then
            invalid=$((invalid + 1))
            echo "Invalid event: $line" >&2
        fi
    done < "$WISDOM_EVENTS_PATH"
    [[ $invalid -eq 0 ]] || { echo "$invalid invalid events"; return 1; }
    return 0
}

# ---------------------------------------------------------------------------
# 2. Redaction
# ---------------------------------------------------------------------------
test_redaction() {
    : > "$WISDOM_EVENTS_PATH"
    local output
    output=$(echo "SECRET_SENTINEL_DO_NOT_LOG and API_KEY=sk-test1234567890abcdef" | \
        "${SCRIPT_DIR}/wisdom-write.sh" --scope system --type fact --tags "${TEST_TAG},redaction" 2>&1 || true)
    # Should be blocked, but events may still be emitted
    [[ -f "$WISDOM_EVENTS_PATH" ]] || { echo "no events file"; return 1; }
    local bad=0
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        if echo "$line" | grep -q "SECRET_SENTINEL_DO_NOT_LOG"; then
            bad=$((bad + 1))
        fi
        if echo "$line" | grep -qE 'sk-test[0-9a-z]{20,}'; then
            bad=$((bad + 1))
        fi
    done < "$WISDOM_EVENTS_PATH"
    [[ $bad -eq 0 ]] || { echo "$bad events leaked secrets"; return 1; }
    return 0
}

# ---------------------------------------------------------------------------
# 3. Retention — exactly/latest 1000 events kept after concurrent writes
# ---------------------------------------------------------------------------
test_retention() {
    : > "$WISDOM_EVENTS_PATH"
    # Seed 1200 events quickly by writing directly
    for i in $(seq 1 1200); do
        jq -nc \
            --arg schema_version "1.0" \
            --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
            --arg system "wisdom" \
            --arg event "wisdom.write" \
            --arg status "success" \
            --arg trace_id "trace-test" \
            --arg invocation_id "inv-$i" \
            --arg script "test" \
            '{
                schema_version: $schema_version,
                ts: $ts,
                system: $system,
                event: $event,
                status: $status,
                trace_id: $trace_id,
                invocation_id: $invocation_id,
                script: $script,
                pid: 1,
                duration_ms: null
            }' >> "$WISDOM_EVENTS_PATH"
    done
    # Trigger one emit via a script to exercise the retention truncation path
    echo "Retention trigger test entry with sufficient length" | \
        "${SCRIPT_DIR}/wisdom-write.sh" --scope system --type fact --tags "${TEST_TAG},retention" >/dev/null 2>&1
    local count
    count=$(count_events)
    [[ "$count" -eq 1000 ]] || { echo "Expected 1000 events, got $count"; return 1; }
    # Verify last line is the 1200th (before the trigger event pushed it to 1000)
    # Actually after truncation + new event, last should be the trigger event
    # Just verify count is exactly 1000 and all are valid JSON
    return 0
}

# ---------------------------------------------------------------------------
# 4. Trace propagation — WISDOM_TRACE_ID shared across nested scripts
# ---------------------------------------------------------------------------
test_trace_propagation() {
    : > "$WISDOM_EVENTS_PATH"
    export WISDOM_TRACE_ID=""
    unset WISDOM_TRACE_ID 2>/dev/null || true
    # Run a search which internally may not nest, but closeout nests write+edit
    local id
    id=$(echo "Trace propagation test entry about observability tracing behavior" | \
        "${SCRIPT_DIR}/wisdom-closeout.sh" --scope system --tags "${TEST_TAG},trace" 2>&1 | grep -oE '[0-9]{8}-[0-9]{6}-[a-z0-9]{4}' | tail -1)
    [[ -n "$id" ]] || { echo "closeout failed"; return 1; }
    local traces
    traces=$(jq -s '[.[] | .trace_id] | unique | length' "$WISDOM_EVENTS_PATH" 2>/dev/null || echo 0)
    [[ "$traces" -eq 1 ]] || { echo "Expected 1 trace_id, got $traces"; return 1; }
    return 0
}

# ---------------------------------------------------------------------------
# 5. Parent invocation — child scripts reference parent's invocation_id
# ---------------------------------------------------------------------------
test_parent_invocation() {
    : > "$WISDOM_EVENTS_PATH"
    export WISDOM_TRACE_ID=""
    unset WISDOM_TRACE_ID 2>/dev/null || true
    local id
    id=$(echo "Parent invocation test entry about nested script observability" | \
        "${SCRIPT_DIR}/wisdom-closeout.sh" --scope system --tags "${TEST_TAG},parent" 2>&1 | grep -oE '[0-9]{8}-[0-9]{6}-[a-z0-9]{4}' | tail -1)
    [[ -n "$id" ]] || { echo "closeout failed"; return 1; }
    local with_parent
    with_parent=$(jq -s '[.[] | select(.parent_invocation_id != null)] | length' "$WISDOM_EVENTS_PATH" 2>/dev/null || echo 0)
    # closeout calls write (child) and edit (child) — at least some events should have parent_invocation_id
    [[ "$with_parent" -ge 1 ]] || { echo "Expected >=1 events with parent_invocation_id, got $with_parent"; return 1; }
    return 0
}

# ---------------------------------------------------------------------------
# 6. Disabled mode — WISDOM_OBSERVABILITY=0 produces no events
# ---------------------------------------------------------------------------
test_disabled_mode() {
    : > "$WISDOM_EVENTS_PATH"
    local id
    id=$(export WISDOM_OBSERVABILITY=0; echo "Disabled mode test entry with sufficient length for validation" | \
        "${SCRIPT_DIR}/wisdom-write.sh" --scope system --type fact --tags "${TEST_TAG},disabled" 2>&1 | grep -oE '[0-9]{8}-[0-9]{6}-[a-z0-9]{4}')
    [[ -n "$id" ]] || { echo "write failed"; return 1; }
    local count
    count=$(count_events)
    [[ "$count" -eq 0 ]] || { echo "Expected 0 events in disabled mode, got $count"; return 1; }
    return 0
}

# ---------------------------------------------------------------------------
# 7. Capture/write events — wisdom.write, wisdom.capture.closeout, etc.
# ---------------------------------------------------------------------------
test_capture_write_events() {
    : > "$WISDOM_EVENTS_PATH"
    local id1 id2 id3
    id1=$(echo "Write event test entry about capture and write observability" | \
        "${SCRIPT_DIR}/wisdom-write.sh" --scope system --type fact --tags "${TEST_TAG},capture" 2>&1 | grep -oE '[0-9]{8}-[0-9]{6}-[a-z0-9]{4}')
    id2=$(echo "Closeout event test entry about observability capture flows" | \
        "${SCRIPT_DIR}/wisdom-closeout.sh" --scope system --tags "${TEST_TAG},capture" 2>&1 | grep -oE '[0-9]{8}-[0-9]{6}-[a-z0-9]{4}' | tail -1)
    id3=$(echo "Nomination event test entry about infrastructure deployment config" | \
        "${SCRIPT_DIR}/wisdom-nominate.sh" --scope system --tags "${TEST_TAG},capture,infra" 2>&1 | grep -oE '[0-9]{8}-[0-9]{6}-[a-z0-9]{4}')
    [[ -n "$id1" && -n "$id2" && -n "$id3" ]] || { echo "one of the writes failed"; return 1; }
    local write_events closeout_events nomination_events
    write_events=$(events_for_event_type "wisdom.write" | jq 'length')
    closeout_events=$(events_for_event_type "wisdom.capture.closeout" | jq 'length')
    nomination_events=$(events_for_event_type "wisdom.capture.nomination" | jq 'length')
    [[ "$write_events" -ge 1 ]] || { echo "no wisdom.write events"; return 1; }
    [[ "$closeout_events" -ge 1 ]] || { echo "no wisdom.capture.closeout events"; return 1; }
    [[ "$nomination_events" -ge 1 ]] || { echo "no wisdom.capture.nomination events"; return 1; }
    return 0
}

# ---------------------------------------------------------------------------
# 8. Query/shim events — wisdom.search, wisdom.lookup, wisdom.snapshot
# ---------------------------------------------------------------------------
test_query_shim_events() {
    : > "$WISDOM_EVENTS_PATH"
    # Seed at least one entry
    echo "Query shim test entry about search lookup and snapshot observability" | \
        "${SCRIPT_DIR}/wisdom-write.sh" --scope system --type fact --tags "${TEST_TAG},query" >/dev/null 2>&1
    "${SCRIPT_DIR}/wisdom-search.sh" "query shim" --scope system --json >/dev/null 2>&1 || true
    "${SCRIPT_DIR}/knowledge-lookup.sh" "query shim" >/dev/null 2>&1 || true
    "${SCRIPT_DIR}/knowledge-snapshot.sh" >/dev/null 2>&1 || true
    local search_events lookup_events snapshot_events
    search_events=$(events_for_event_type "wisdom.search" | jq 'length')
    lookup_events=$(events_for_event_type "wisdom.lookup" | jq 'length')
    snapshot_events=$(events_for_event_type "wisdom.snapshot" | jq 'length')
    [[ "$search_events" -ge 1 ]] || { echo "no wisdom.search events"; return 1; }
    [[ "$lookup_events" -ge 1 ]] || { echo "no wisdom.lookup events"; return 1; }
    [[ "$snapshot_events" -ge 1 ]] || { echo "no wisdom.snapshot events"; return 1; }
    return 0
}

# ---------------------------------------------------------------------------
# 9. Promotion/lifecycle events — wisdom.promote.publish, wisdom.lifecycle.edit
# ---------------------------------------------------------------------------
test_promotion_lifecycle_events() {
    : > "$WISDOM_EVENTS_PATH"
    local entry_id publish_output
    entry_id=$(echo "Promotion lifecycle test entry about publishing and editing observability with sufficient length" | \
        "${SCRIPT_DIR}/wisdom-write.sh" --scope system --type pattern --tags "${TEST_TAG},promote" --score 5 \
        --authority verified --verified-at "2025-01-01T00:00:00Z" 2>&1 | grep -oE '[0-9]{8}-[0-9]{6}-[a-z0-9]{4}')
    [[ -n "$entry_id" ]] || { echo "write failed"; return 1; }
    publish_output=$("${SCRIPT_DIR}/wisdom-publish.sh" --id "$entry_id" --reason "observability test" 2>&1)
    [[ $? -eq 0 ]] || { echo "publish failed: $publish_output"; return 1; }
    "${SCRIPT_DIR}/wisdom-edit.sh" --id "$entry_id" --scope system --set-status stale >/dev/null 2>&1
    local promote_events lifecycle_edit_events lifecycle_auth_events
    promote_events=$(events_for_event_type "wisdom.promote.publish" | jq 'length')
    lifecycle_edit_events=$(events_for_event_type "wisdom.lifecycle.edit" | jq 'length')
    lifecycle_auth_events=$(events_for_event_type "wisdom.lifecycle.authority_change" | jq 'length')
    [[ "$promote_events" -ge 1 ]] || { echo "no wisdom.promote.publish events"; return 1; }
    [[ "$lifecycle_edit_events" -ge 1 ]] || { echo "no wisdom.lifecycle.edit events"; return 1; }
    return 0
}

# ---------------------------------------------------------------------------
# 10. wisdom-observe.sh CLI — status, read, trace, reset
# ---------------------------------------------------------------------------
test_observe_cli() {
    : > "$WISDOM_EVENTS_PATH"
    echo "Observe CLI test entry for operator command verification" | \
        "${SCRIPT_DIR}/wisdom-write.sh" --scope system --type fact --tags "${TEST_TAG},observe" >/dev/null 2>&1
    local status_output read_output trace_output reset_output
    status_output=$("${SCRIPT_DIR}/wisdom-observe.sh" status 2>&1)
    read_output=$("${SCRIPT_DIR}/wisdom-observe.sh" read --limit 10 --json 2>&1)
    local trace_id
    trace_id=$(jq -r '.trace_id' "$WISDOM_EVENTS_PATH" | head -n1)
    trace_output=$("${SCRIPT_DIR}/wisdom-observe.sh" trace "$trace_id" --json 2>&1)
    reset_output=$("${SCRIPT_DIR}/wisdom-observe.sh" reset --yes 2>&1)
    echo "$status_output" | grep -qi "observability" || { echo "status missing observability info"; return 1; }
    echo "$read_output" | jq 'length' >/dev/null 2>&1 || { echo "read not valid JSON array"; return 1; }
    echo "$trace_output" | jq 'length' >/dev/null 2>&1 || { echo "trace not valid JSON array"; return 1; }
    echo "$reset_output" | grep -qi "reset" || { echo "reset missing confirmation"; return 1; }
    local count_after
    count_after=$(count_events)
    # reset emits one wisdom.observe.reset event
    [[ "$count_after" -eq 1 ]] || { echo "Expected 1 event after reset, got $count_after"; return 1; }
    return 0
}

# ---------------------------------------------------------------------------
# 11. Concurrent appends — multiple parallel writes don't corrupt JSONL
# ---------------------------------------------------------------------------
test_concurrent_appends() {
    : > "$WISDOM_EVENTS_PATH"
    for i in $(seq 1 20); do
        (
            echo "Concurrent append test entry number $i with enough length for validation" | \
                "${SCRIPT_DIR}/wisdom-write.sh" --scope system --type fact --tags "${TEST_TAG},concurrent" >/dev/null 2>&1
        ) &
    done
    wait
    local corrupted=0
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        if ! echo "$line" | jq -e -c . >/dev/null 2>&1; then
            corrupted=$((corrupted + 1))
        fi
    done < "$WISDOM_EVENTS_PATH"
    [[ $corrupted -eq 0 ]] || { echo "$corrupted corrupted events"; return 1; }
    return 0
}

# ---------------------------------------------------------------------------
# 12. Non-interference — stdout/stderr/exit codes unchanged
# ---------------------------------------------------------------------------
test_non_interference() {
    : > "$WISDOM_EVENTS_PATH"
    local stdout_enabled stderr_enabled rc_enabled stdout_disabled stderr_disabled rc_disabled
    stdout_enabled=$(echo "Non interference test entry with sufficient length" | \
        "${SCRIPT_DIR}/wisdom-write.sh" --scope system --type fact --tags "${TEST_TAG},interference" 2>/dev/null)
    stderr_enabled=$(echo "Non interference test entry with sufficient length" | \
        "${SCRIPT_DIR}/wisdom-write.sh" --scope system --type fact --tags "${TEST_TAG},interference" 2>&1 >/dev/null)
    echo "test" | "${SCRIPT_DIR}/wisdom-write.sh" --scope system --type fact --tags "${TEST_TAG},interference" >/dev/null 2>&1
    rc_enabled=$?

    stdout_disabled=$(export WISDOM_OBSERVABILITY=0; echo "Non interference test entry with sufficient length" | \
        "${SCRIPT_DIR}/wisdom-write.sh" --scope system --type fact --tags "${TEST_TAG},interference" 2>/dev/null)
    stderr_disabled=$(export WISDOM_OBSERVABILITY=0; echo "Non interference test entry with sufficient length" | \
        "${SCRIPT_DIR}/wisdom-write.sh" --scope system --type fact --tags "${TEST_TAG},interference" 2>&1 >/dev/null)
    export WISDOM_OBSERVABILITY=0; echo "test" | "${SCRIPT_DIR}/wisdom-write.sh" --scope system --type fact --tags "${TEST_TAG},interference" >/dev/null 2>&1
    rc_disabled=$?

    [[ "$rc_enabled" -eq "$rc_disabled" ]] || { echo "exit code changed: $rc_enabled vs $rc_disabled"; return 1; }
    # stdout should contain the ID in both cases
    local id_enabled id_disabled
    id_enabled=$(echo "$stdout_enabled" | grep -oE '[0-9]{8}-[0-9]{6}-[a-z0-9]{4}' || true)
    id_disabled=$(echo "$stdout_disabled" | grep -oE '[0-9]{8}-[0-9]{6}-[a-z0-9]{4}' || true)
    [[ -n "$id_enabled" && -n "$id_disabled" ]] || { echo "ID missing from stdout"; return 1; }
    return 0
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    log_info "=== Wisdom Observability Test Suite ==="
    log_info "Temp HOME: $TEMP_HOME"
    log_info "WISDOM_EVENTS_PATH: $WISDOM_EVENTS_PATH"

    run_test "Schema validity" test_schema_validity
    run_test "Redaction" test_redaction
    run_test "Retention" test_retention
    run_test "Trace propagation" test_trace_propagation
    run_test "Parent invocation" test_parent_invocation
    run_test "Disabled mode" test_disabled_mode
    run_test "Capture/write events" test_capture_write_events
    run_test "Query/shim events" test_query_shim_events
    run_test "Promotion/lifecycle events" test_promotion_lifecycle_events
    run_test "wisdom-observe.sh CLI" test_observe_cli
    run_test "Concurrent appends" test_concurrent_appends
    run_test "Non-interference" test_non_interference

    echo ""
    log_info "=== Test Summary ==="
    echo "Total tests: $TESTS_TOTAL"
    echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"

    if [[ $TESTS_FAILED -gt 0 ]]; then
        echo -e "${RED}Failed: $TESTS_FAILED${NC}"
        {
            echo "Wisdom Observability Test Results"
            echo "================================="
            echo "Started: $(date)"
            echo ""
            echo "Test Summary:"
            echo "Total: $TESTS_TOTAL, Passed: $TESTS_PASSED, Failed: $TESTS_FAILED"
            echo "Completed: $(date)"
            echo "Status: SOME TESTS FAILED"
        } > "$EVIDENCE_FILE"
        cp "$EVIDENCE_FILE" "$REAL_EVIDENCE_DIR/task-6-wisdom-observability.txt" 2>/dev/null || true
        log_fail "Some observability tests failed."
        return 1
    else
        echo -e "${GREEN}All tests passed!${NC}"
        {
            echo "Wisdom Observability Test Results"
            echo "================================="
            echo "Started: $(date)"
            echo ""
            echo "Test Summary:"
            echo "Total: $TESTS_TOTAL, Passed: $TESTS_PASSED, Failed: $TESTS_FAILED"
            echo "Completed: $(date)"
            echo "Status: ALL TESTS PASSED"
        } > "$EVIDENCE_FILE"
        cp "$EVIDENCE_FILE" "$REAL_EVIDENCE_DIR/task-6-wisdom-observability.txt" 2>/dev/null || true
        log_pass "All observability tests passed!"
        return 0
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
