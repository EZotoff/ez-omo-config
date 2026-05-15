#!/usr/bin/env bash

# Test skills/update-to-latest/SKILL.md contains all required safety guardrails.
# Purely textual grep-based verification — no network, no package manager, no updates.
# Usage: bash tests/test_update_to_latest_skill.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/helpers.sh"

SKILL_FILE="$REPO_ROOT/skills/update-to-latest/SKILL.md"

echo "=== Guardrail 1: Explicit human approval requirement ==="
assert_grep 'YES, update OpenCode/OMO now' "$SKILL_FILE"

echo "=== Guardrail 2: No update before approval gate ==="
assert_grep 'do not run package manager' "$SKILL_FILE"

echo "=== Guardrail 3: Recommendation-only stop condition ==="
assert_grep 'If the user has not explicitly asked to execute the update now, stop after producing the update recommendation' "$SKILL_FILE"

echo "=== Guardrail 4: Backup/rollback bundle creation path ==="
assert_grep '~/.ez-omo-backup/update-to-latest/' "$SKILL_FILE"

echo "=== Guardrail 5: Rollback drill only for Deep/high-risk ==="
assert_grep 'rollback drill' "$SKILL_FILE"
assert_grep 'high-risk' "$SKILL_FILE"

echo "=== Guardrail 6: Patch deprecate-not-delete rule ==="
assert_grep 'deprecate' "$SKILL_FILE"
assert_grep 'do not delete' "$SKILL_FILE"

echo "=== Guardrail 7: Light/Standard/Deep regression levels ==="
assert_grep 'Light' "$SKILL_FILE"
assert_grep 'Standard' "$SKILL_FILE"
assert_grep 'Deep' "$SKILL_FILE"

echo "=== Guardrail 8: Release discovery via GitHub Releases API ==="
assert_grep 'GitHub Releases API' "$SKILL_FILE"
assert_grep 'anomalyco/opencode' "$SKILL_FILE"
assert_grep 'code-yeongyu/oh-my-openagent' "$SKILL_FILE"

echo "=== Guardrail 9: Evidence-state claim discipline ==="
assert_grep 'repo_implemented' "$SKILL_FILE"
assert_grep 'real_project_behavior_proven' "$SKILL_FILE"

echo "=== Guardrail 10: Scope exclusion — not an automatic updater ==="
assert_grep 'NOT an automatic updater' "$SKILL_FILE"

echo "=== Guardrail 11: Anti-pattern — opencode upgrade is not a discovery command ==="
assert_grep 'opencode upgrade' "$SKILL_FILE"
assert_grep 'not a discovery or check command' "$SKILL_FILE"

echo "=== Guardrail 12: Concrete OpenCode discovery cascade ==="
assert_grep 'gh release view --repo anomalyco/opencode' "$SKILL_FILE"
assert_grep 'gh api repos/anomalyco/opencode/releases/latest' "$SKILL_FILE"
assert_grep 'npm view opencode-ai version' "$SKILL_FILE"

echo "=== Guardrail 13: Concrete OMO discovery cascade ==="
assert_grep 'gh release view --repo code-yeongyu/oh-my-openagent' "$SKILL_FILE"
assert_grep 'gh api repos/code-yeongyu/oh-my-openagent/releases/latest' "$SKILL_FILE"
assert_grep 'npm view oh-my-openagent version' "$SKILL_FILE"

echo "=== Guardrail 14: Vague failure language is forbidden before exhausting fallbacks ==="
assert_grep 'Could not determine exact number' "$SKILL_FILE"
assert_grep 'unless every fallback' "$SKILL_FILE"

echo "=== Guardrail 15: Structured blocker report requirement ==="
assert_grep 'structured blocker report' "$SKILL_FILE"
assert_grep 'attempted' "$SKILL_FILE"
assert_grep 'next manual command' "$SKILL_FILE"

echo "=== Guardrail 16: Output contract with source tracking ==="
assert_grep 'source of installed value' "$SKILL_FILE"
assert_grep 'source of latest value' "$SKILL_FILE"
assert_grep 'confidence / caveat' "$SKILL_FILE"

echo "=== Guardrail 17: Installed-version discovery instructions ==="
assert_grep 'opencode --version' "$SKILL_FILE"
assert_grep 'installed version' "$SKILL_FILE"

echo "=== Guardrail 18: Configured local path is not runtime-loaded proof ==="
assert_grep 'configured in active config as a local file path' "$SKILL_FILE"
assert_grep 'Do not claim this from config alone' "$SKILL_FILE"
assert_grep 'Not verified live: runtime_loaded' "$SKILL_FILE"

echo "=== Guardrail 19: Blind git pull is forbidden for local OMO checkout ==="
assert_grep 'Do NOT prescribe `git pull`' "$SKILL_FILE"
assert_grep 'not be a one-line `git pull`' "$SKILL_FILE"
assert_grep 'dedicated local-source update plan' "$SKILL_FILE"

echo "=== Guardrail 20: Local OMO checkout inventory must include branch and dirty state ==="
assert_grep 'git status --short --branch' "$SKILL_FILE"
assert_grep 'git remote -v' "$SKILL_FILE"
assert_grep 'ahead/behind state' "$SKILL_FILE"

echo "=== Guardrail 21: Local source updates use non-mutating discovery before approval ==="
assert_grep 'git fetch --all --tags --prune' "$SKILL_FILE"
assert_grep 'Do not run `git pull`, `git checkout`, `git reset`, `npm install`, or build commands before the explicit approval gate' "$SKILL_FILE"

echo "=== Guardrail 22: Session-continuity warning for active TUI risk ==="
assert_grep 'session-continuity warning' "$SKILL_FILE"
assert_grep 'interruption risk' "$SKILL_FILE"

echo ""
echo "=========================================="
echo "Tests passed: $TESTS_PASSED"
echo "Tests failed: $TESTS_FAILED"
echo "=========================================="

if [[ $TESTS_FAILED -gt 0 ]]; then
    exit 1
fi

exit 0
