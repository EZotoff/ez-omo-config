#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo "=== Contract 1: verify-live-deployment.sh exists and passes bash -n ==="
assert_file_exists "$REPO_ROOT/scripts/verify-live-deployment.sh"
if bash -n "$REPO_ROOT/scripts/verify-live-deployment.sh"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "FAIL: scripts/verify-live-deployment.sh fails bash -n syntax check"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

DRY_RUN_OUTPUT=""
HELP_OUTPUT="$(mktemp)"
trap 'rm -f "$DRY_RUN_OUTPUT" "$HELP_OUTPUT"' EXIT
bash "$REPO_ROOT/scripts/verify-live-deployment.sh" --help > "$HELP_OUTPUT"
assert_grep 'live-target' "$HELP_OUTPUT"
assert_grep 'config-reference' "$HELP_OUTPUT"
assert_grep 'runtime-evidence' "$HELP_OUTPUT"
assert_no_grep 'probe-query' "$HELP_OUTPUT"

echo "=== Contract 2: install.sh --dry-run --scripts includes verify-live-deployment.sh ==="
DRY_RUN_OUTPUT="$(mktemp)"
HOME="$REPO_ROOT/tests/fake-home-$$" bash "$REPO_ROOT/install.sh" --dry-run --scripts >"$DRY_RUN_OUTPUT" 2>&1 || true
assert_grep 'verify-live-deployment.sh' "$DRY_RUN_OUTPUT"

echo "=== Contract 3: Evidence-state language in required files ==="
assert_grep 'repo_implemented' "$REPO_ROOT/AGENTS.md"
assert_grep 'live config/runtime state' "$REPO_ROOT/skills/wisdom/SKILL.md"
assert_grep 'active_config_registered' "$REPO_ROOT/plugins/review-enforcer.ts"
assert_grep 'real_project_behavior_proven' "$REPO_ROOT/configs/oh-my-openagent/oh-my-openagent.json"

echo "=== Contract 4: run_all.sh does not auto-run real external-project probes ==="
assert_no_grep '/home/ezotoff/AI_projects' "$REPO_ROOT/tests/run_all.sh"
assert_no_grep 'live.?probe' "$REPO_ROOT/tests/run_all.sh"
assert_no_grep 'ANIA' "$REPO_ROOT/tests/run_all.sh"

echo "Tests passed: $TESTS_PASSED"
echo "Tests failed: $TESTS_FAILED"
if [[ $TESTS_FAILED -gt 0 ]]; then
    exit 1
fi
exit 0
