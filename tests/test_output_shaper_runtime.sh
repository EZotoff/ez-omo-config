#!/usr/bin/env bash

# Output Shaper runtime harness regression wrapper
# Runs all harness test cases and exits 0 if all pass

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ -f "$SCRIPT_DIR/helpers.sh" ]]; then
    source "$SCRIPT_DIR/helpers.sh"
fi

HARNESS="$SCRIPT_DIR/output-shaper/harness.mjs"

# fail-closed-no-config exercises the missing-config branch of loadConfig():
# with no test override, loadConfig() reads $HOME/.config/opencode/
# oh-my-openagent.json — a live symlink that HAS the outputShaper block. To
# prove the no-config fail-closed path without mutating live config, run every
# node invocation under a throwaway HOME so the config file is absent. All
# other cases inject config via setTestConfig() and are unaffected.
FAKE_HOME="$(mktemp -d -t output-shaper-home.XXXXXX 2>/dev/null || printf '%s' "/tmp/output-shaper-test-home")"
mkdir -p "$FAKE_HOME"
trap 'rm -rf "$FAKE_HOME"' EXIT

TOTAL_PASSED=0
TOTAL_FAILED=0

run_case() {
    local case_name="$1"
    echo "Running: $case_name"
    if HOME="$FAKE_HOME" node "$HARNESS" --case "$case_name"; then
        TOTAL_PASSED=$((TOTAL_PASSED + 1))
    else
        TOTAL_FAILED=$((TOTAL_FAILED + 1))
        echo "FAIL: $case_name"
    fi
}

run_case "terseness-injected"
run_case "terseness-static"
run_case "glm-resume-clamped"
run_case "kimi-resume-clamped"
run_case "gpt-resume-clamped"
run_case "gemini-resume-clamped"
run_case "claude-resume-not-clamped"
run_case "copilot-resume-not-clamped"
run_case "new-question-not-clamped"
run_case "casing-snake-vs-camel"
run_case "fail-closed-no-config"
run_case "disabled-config"

echo ""
echo "=========================================="
echo "Output Shaper runtime: $TOTAL_PASSED passed, $TOTAL_FAILED failed"
echo "=========================================="

if [[ $TOTAL_FAILED -gt 0 ]]; then
    exit 1
fi

exit 0
