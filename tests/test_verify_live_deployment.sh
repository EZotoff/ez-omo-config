#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VERIFY_SCRIPT="$REPO_ROOT/scripts/verify-live-deployment.sh"

source "$SCRIPT_DIR/helpers.sh"

TMP_HOME="$(mktemp -d)"
TMP_PROJECT="$(mktemp -d)"
TMP_EVIDENCE_BASE="$(mktemp -d)"
trap 'rm -rf "$TMP_HOME" "$TMP_PROJECT" "$TMP_EVIDENCE_BASE"' EXIT

mkdir -p "$TMP_HOME/.config/opencode"
ln -s "$REPO_ROOT/configs/opencode/opencode.json" "$TMP_HOME/.config/opencode/opencode.json"
git init -q "$TMP_PROJECT"

run_verifier() {
    local evidence_dir="$1"
    shift
    HOME="$TMP_HOME" bash "$VERIFY_SCRIPT" \
        --component config-smoke \
        --project "$TMP_PROJECT" \
        --evidence-dir "$evidence_dir" \
        "$@"
}

BASE_EVIDENCE="$TMP_EVIDENCE_BASE/base"
run_verifier "$BASE_EVIDENCE"
assert_file_exists "$BASE_EVIDENCE/summary.json"
assert_file_exists "$BASE_EVIDENCE/commands.txt"
assert_file_exists "$BASE_EVIDENCE/live-paths.txt"
assert_file_exists "$BASE_EVIDENCE/active-config-plugin-array.json"
assert_grep '"overall": "passed"' "$BASE_EVIDENCE/summary.json"
assert_grep '"highest_state": "live_file_installed"' "$BASE_EVIDENCE/summary.json"
assert_grep '"check": "project_is_git_repo"' "$BASE_EVIDENCE/summary.json"

LIVE_TARGET="$TMP_EVIDENCE_BASE/live-target.txt"
RUNTIME_EVIDENCE="$TMP_EVIDENCE_BASE/runtime.log"
printf 'installed artifact\n' > "$LIVE_TARGET"
printf 'runtime handler invoked\n' > "$RUNTIME_EVIDENCE"

RUNTIME_EVIDENCE_DIR="$TMP_EVIDENCE_BASE/runtime"
run_verifier "$RUNTIME_EVIDENCE_DIR" \
    --live-target "$LIVE_TARGET" \
    --config-reference '"plugin"' \
    --runtime-evidence "$RUNTIME_EVIDENCE"
assert_grep '"overall": "passed"' "$RUNTIME_EVIDENCE_DIR/summary.json"
assert_grep '"highest_state": "runtime_loaded"' "$RUNTIME_EVIDENCE_DIR/summary.json"
assert_grep '"check": "live_target"' "$RUNTIME_EVIDENCE_DIR/summary.json"
assert_grep '"check": "active_config_reference"' "$RUNTIME_EVIDENCE_DIR/summary.json"
assert_grep '"check": "runtime_evidence"' "$RUNTIME_EVIDENCE_DIR/summary.json"
assert_file_exists "$RUNTIME_EVIDENCE_DIR/runtime-evidence.txt"

MISSING_EVIDENCE_DIR="$TMP_EVIDENCE_BASE/missing"
if HOME="$TMP_HOME" bash "$VERIFY_SCRIPT" \
    --component config-smoke \
    --project "$TMP_PROJECT" \
    --evidence-dir "$MISSING_EVIDENCE_DIR" \
    --live-target "$TMP_EVIDENCE_BASE/missing-target" >/dev/null 2>&1; then
    echo "FAIL: missing live target should fail verification"
    TESTS_FAILED=$((TESTS_FAILED + 1))
else
    TESTS_PASSED=$((TESTS_PASSED + 1))
    assert_file_exists "$MISSING_EVIDENCE_DIR/summary.json"
    assert_grep '"failure_code": "live_target_missing"' "$MISSING_EVIDENCE_DIR/summary.json"
fi

echo "Tests passed: $TESTS_PASSED"
echo "Tests failed: $TESTS_FAILED"
if [[ $TESTS_FAILED -gt 0 ]]; then
    exit 1
fi
exit 0
