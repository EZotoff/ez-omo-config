#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CLASSIFIER="$REPO_ROOT/scripts/path-classifier.py"
EVIDENCE_DIR="$REPO_ROOT/.sisyphus/evidence/opencode-omo-transition"

TESTS_PASSED=0
TESTS_FAILED=0

record_pass() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

record_fail() {
    local message="$1"
    echo "FAIL: $message" >&2
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

classify_json() {
    python3 "$CLASSIFIER" --json "$1"
}

assert_classification() {
    local path="$1"
    local expected="$2"
    local actual
    actual="$(classify_json "$path" | python3 -c 'import json,sys; print(json.load(sys.stdin)["classification"])')"
    if [[ "$actual" == "$expected" ]]; then
        record_pass
    else
        record_fail "$path classified as $actual, expected $expected"
    fi
}

assert_writable() {
    local path="$1"
    local expected="$2"
    local actual
    actual="$(classify_json "$path" | python3 -c 'import json,sys; print(str(json.load(sys.stdin)["writable"]).lower())')"
    if [[ "$actual" == "$expected" ]]; then
        record_pass
    else
        record_fail "$path writable=$actual, expected $expected"
    fi
}

assert_command_succeeds() {
    local description="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        record_pass
    else
        record_fail "$description should succeed"
    fi
}

assert_command_fails() {
    local description="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        record_fail "$description should fail"
    else
        record_pass
    fi
}

mkdir -p "$EVIDENCE_DIR"

assert_classification "/home/ezotoff/ez-omo-config/configs/opencode/opencode.json" "control_plane"
assert_classification "/home/ezotoff/oh-my-openagent/package.json" "source_plane"
assert_classification "/home/ezotoff/ez-omo-config/.sisyphus/plans/opencode-omo-transition.md" "planning_state"

assert_classification "/home/ezotoff/.local/share/opencode/auth.json" "secret_or_auth"
assert_classification "/home/ezotoff/ez-omo-config/.omo" "forbidden_zone"
assert_classification "/tmp/ez-omo-stack-classifier-unknown" "unknown"

assert_writable "/home/ezotoff/ez-omo-config/configs/opencode/opencode.json" "true"
assert_writable "/home/ezotoff/ez-omo-config/.sisyphus" "true"
assert_writable "/home/ezotoff/.local/share/opencode/auth.json" "false"
assert_writable "/home/ezotoff/ez-omo-config/.omo" "false"
assert_writable "/tmp/ez-omo-stack-classifier-unknown" "false"

assert_command_succeeds "writable control-plane path" \
    python3 "$CLASSIFIER" --writable "/home/ezotoff/ez-omo-config/configs/opencode/opencode.json"
assert_command_fails "non-writable auth path" \
    python3 "$CLASSIFIER" --writable "/home/ezotoff/.local/share/opencode/auth.json"
assert_command_fails "strict forbidden path" \
    python3 "$CLASSIFIER" --strict "/home/ezotoff/ez-omo-config/.omo"
assert_command_fails "strict unknown path" \
    python3 "$CLASSIFIER" --strict "/tmp/ez-omo-stack-classifier-unknown"

python3 "$CLASSIFIER" --json "/home/ezotoff/ez-omo-config/configs/opencode/opencode.json" \
    > "$EVIDENCE_DIR/task-2-classifier-positive.json"
python3 "$CLASSIFIER" --json "/home/ezotoff/ez-omo-config/.omo" \
    > "$EVIDENCE_DIR/task-2-classifier-forbidden.json"

echo "Stack path classifier tests: $TESTS_PASSED passed, $TESTS_FAILED failed"
if [[ "$TESTS_FAILED" -ne 0 ]]; then
    exit 1
fi
