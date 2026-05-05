#!/usr/bin/env bash

# Test live deployment contracts — repo-safe checks only.
# Does NOT require live OpenCode runtime or external projects.
# Usage: bash tests/test_live_deployment_contract.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/helpers.sh"

echo "=== Contract 1: verify-live-deployment.sh exists and passes bash -n ==="
assert_file_exists "scripts/verify-live-deployment.sh"
if bash -n "$REPO_ROOT/scripts/verify-live-deployment.sh"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "FAIL: scripts/verify-live-deployment.sh fails bash -n syntax check"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo "=== Contract 2: install.sh --dry-run --scripts includes verify-live-deployment.sh ==="
DRY_RUN_OUTPUT="$(mktemp)"
trap 'rm -f "$DRY_RUN_OUTPUT"' EXIT

HOME="$REPO_ROOT/tests/fake-home-$$" bash "$REPO_ROOT/install.sh" --dry-run --scripts >"$DRY_RUN_OUTPUT" 2>&1 || true
assert_grep 'verify-live-deployment.sh' "$DRY_RUN_OUTPUT"

echo "=== Contract 3: vera-runtime is HOME-autoloaded and config-registered ==="
assert_file_exists "plugins/vera-runtime.ts"
assert_grep 'vera-runtime.ts' "configs/opencode/opencode.json"

echo "=== Contract 4: Evidence-state language in required files ==="
assert_grep 'repo_implemented' "AGENTS.md"
assert_grep 'live config or runtime state' "skills/wisdom/SKILL.md"
assert_grep 'active_config_registered' "plugins/review-enforcer.ts"
assert_grep 'real_project_behavior_proven' "configs/oh-my-openagent/oh-my-openagent.json"

echo "=== Contract 5: run_all.sh does not auto-run real external-project probes ==="
assert_no_grep 'ANIA' "tests/run_all.sh"
assert_no_grep '/home/ezotoff/AI_projects' "tests/run_all.sh"
assert_no_grep 'live.?probe' "tests/run_all.sh"

echo ""
echo "=========================================="
echo "Tests passed: $TESTS_PASSED"
echo "Tests failed: $TESTS_FAILED"
echo "=========================================="

if [[ $TESTS_FAILED -gt 0 ]]; then
    exit 1
fi

exit 0
