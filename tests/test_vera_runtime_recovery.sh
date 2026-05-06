#!/usr/bin/env bash

# Contract tests for vera runtime recovery scenarios.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PLUGIN_FILE="$REPO_ROOT/plugins/vera-runtime.ts"

TESTS_PASSED=0
TESTS_FAILED=0

assert_contains() {
    local needle="$1"
    local haystack="$2"
    local message="$3"

    if [[ "$haystack" == *"$needle"* ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    fi

    echo "FAIL: $message (missing '$needle')"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    return 1
}

assert_not_contains() {
    local needle="$1"
    local haystack="$2"
    local message="$3"

    if [[ "$haystack" != *"$needle"* ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    fi

    echo "FAIL: $message (unexpected '$needle')"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    return 1
}

scenario_indexed_hollow_recovery() {
    echo "=== Scenario: indexed-hollow-recovery ==="

    if [[ ! -f "$PLUGIN_FILE" ]]; then
        echo "FAIL: Plugin file not found: $PLUGIN_FILE"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi

    local plugin_src
    plugin_src="$(cat "$PLUGIN_FILE")"

    assert_contains "function isVeraIndexNonEmpty(workspacePath: string): boolean" "$plugin_src" "isVeraIndexNonEmpty function missing"
    assert_contains '"vera", "overview"' "$plugin_src" "vera overview invocation missing"
    assert_contains "Files:" "$plugin_src" "Files parse missing"
    assert_contains "Chunks:" "$plugin_src" "Chunks parse missing"
    assert_contains "parse failure" "$plugin_src" "parse failure handling missing"
    assert_contains 'else if (state.status === "indexed")' "$plugin_src" "indexed branch missing"
    assert_contains "isVeraIndexNonEmpty(directory)" "$plugin_src" "isVeraIndexNonEmpty call missing"
    assert_contains "runVeraHygieneCheck" "$plugin_src" "runVeraHygieneCheck missing"

    local indexed_block
    indexed_block="$(awk '/else if \(state.status === "indexed"\)/,/else if \(state.status === "running"\)/' "$PLUGIN_FILE")"
    if [[ "$indexed_block" == *"isVeraIndexNonEmpty(directory)"* && "$indexed_block" == *"startVeraWatch(directory)"* ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "FAIL: indexed branch missing isVeraIndexNonEmpty before startVeraWatch"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi

    assert_contains 'status = "index-failed"' "$plugin_src" "index-failed status missing"
    assert_contains "vera-hygiene --apply" "$plugin_src" "actionable hygiene hint missing"
    assert_contains "lastHygieneCheckAt" "$plugin_src" "lastHygieneCheckAt field missing"

    echo "=== indexed-hollow-recovery complete ==="
}

scenario_safe_restart() {
    echo "=== Scenario: safe-restart ==="

    if [[ ! -f "$PLUGIN_FILE" ]]; then
        echo "FAIL: Plugin file not found: $PLUGIN_FILE"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi

    local plugin_src
    plugin_src="$(cat "$PLUGIN_FILE")"

    assert_contains "MAX_RESTART_ATTEMPTS = 3" "$plugin_src" "MAX_RESTART_ATTEMPTS constant missing"
    assert_contains "RESTART_WINDOW_MS = 10 * 60 * 1000" "$plugin_src" "RESTART_WINDOW_MS constant missing"
    assert_contains "function performSafeRestart" "$plugin_src" "performSafeRestart function missing"
    assert_contains "validatePidOwnership" "$plugin_src" "validatePidOwnership missing"
    assert_contains "vera watch" "$plugin_src" "vera watch ownership check missing"

    local code_lines
    code_lines="$(grep -v 'log("' "$PLUGIN_FILE" | grep -v '^\s*//')"
    if echo "$code_lines" | grep -E '\b(killall|pkill|kill\s+[^-])' | grep -v 'kill -0' | grep -v 'kill \${' | grep -v 'kill String' | grep -v 'kill -9' >/dev/null 2>&1; then
        local bad_kill
        bad_kill="$(echo "$code_lines" | grep -E '\b(killall|pkill|kill\s+[^-])' | grep -v 'kill -0' | grep -v 'kill \${' | grep -v 'kill String' | grep -v 'kill -9' | head -1)"
        echo "FAIL: Broad or unsafe kill pattern detected: $bad_kill"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    else
        TESTS_PASSED=$((TESTS_PASSED + 1))
    fi

    assert_contains "function canAttemptRestart" "$plugin_src" "canAttemptRestart missing"
    assert_contains "recordRestartAttempt" "$plugin_src" "recordRestartAttempt missing"
    assert_contains "resetRestartAttempts" "$plugin_src" "resetRestartAttempts missing"
    assert_contains 'status = "watch-failed"' "$plugin_src" "watch-failed status missing"
    assert_contains "performSafeRestart(directory, state)" "$plugin_src" "health loop safe restart missing"
    assert_contains "restartAttempts?: number" "$plugin_src" "restartAttempts field missing"
    assert_contains "lastRestartAttemptAt?: string | null" "$plugin_src" "lastRestartAttemptAt field missing"

    echo "=== safe-restart complete ==="
}

main() {
    local scenario=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --scenario)
                shift
                scenario="${1:-}"
                ;;
            *)
                echo "Unknown option: $1"
                exit 2
                ;;
        esac
        shift
    done

    if [[ -n "$scenario" ]]; then
        case "$scenario" in
            indexed-hollow-recovery)
                scenario_indexed_hollow_recovery
                ;;
            safe-restart)
                scenario_safe_restart
                ;;
            *)
                echo "Unknown scenario: $scenario"
                exit 2
                ;;
        esac
    else
        scenario_indexed_hollow_recovery
        scenario_safe_restart
    fi

    echo ""
    echo "Results: $TESTS_PASSED passed, $TESTS_FAILED failed"

    if [[ $TESTS_FAILED -gt 0 ]]; then
        exit 1
    fi
}

main "$@"
