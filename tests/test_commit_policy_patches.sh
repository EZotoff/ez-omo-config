#!/usr/bin/env bash

# Verify commit policy patches: old strings absent, canonical policy present,
# safety guardrails intact. Skips missing files (run after clone/patch tasks).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

FILES_SKIPPED=0

assert_file_or_skip() {
    local file="$1"
    shift
    local assertion_fn="$1"
    shift

    if [[ ! -f "$file" ]]; then
        echo "SKIP: File not found (Task may not be complete yet): $file"
        FILES_SKIPPED=$((FILES_SKIPPED + 1))
        return 0
    fi

    "$assertion_fn" "$@"
}

OPENCODE_TARGETS=(
    "/home/ezotoff/src/opencode/packages/opencode/src/tool/bash.txt"
    "/home/ezotoff/src/opencode/packages/opencode/src/session/prompt/trinity.txt"
    "/home/ezotoff/src/opencode/packages/opencode/src/session/prompt/default.txt"
)

OMO_AGENT_TARGETS=(
    "/home/ezotoff/oh-my-openagent/src/agents/sisyphus.ts"
    "/home/ezotoff/oh-my-openagent/src/agents/sisyphus/default.ts"
    "/home/ezotoff/oh-my-openagent/src/agents/sisyphus/gpt-5-4.ts"
    "/home/ezotoff/oh-my-openagent/AGENTS.md"
)

OMO_GITMASTER_TARGETS=(
    "/home/ezotoff/oh-my-openagent/src/features/builtin-skills/git-master/SKILL.md"
    "/home/ezotoff/oh-my-openagent/src/features/builtin-skills/skills/git-master-sections/commit-workflow.ts"
)

PROMETHEUS_TARGETS=(
    "/home/ezotoff/oh-my-openagent/src/agents/prometheus/plan-template.ts"
    "/home/ezotoff/oh-my-openagent/src/agents/prometheus/gpt.ts"
    "/home/ezotoff/oh-my-openagent/src/agents/prometheus/identity-constraints.ts"
)

ALL_TARGETS=(
    "${OPENCODE_TARGETS[@]}"
    "${OMO_AGENT_TARGETS[@]}"
    "${OMO_GITMASTER_TARGETS[@]}"
    "${PROMETHEUS_TARGETS[@]}"
)

CANONICAL_POLICY_TARGETS=(
    "${OPENCODE_TARGETS[@]}"
    "${OMO_AGENT_TARGETS[@]}"
    "${PROMETHEUS_TARGETS[@]}"
)

SAFETY_TARGETS=(
    "/home/ezotoff/src/opencode/packages/opencode/src/tool/bash.txt"
    "/home/ezotoff/oh-my-openagent/src/features/builtin-skills/git-master/SKILL.md"
    "/home/ezotoff/oh-my-openagent/src/features/builtin-skills/skills/git-master-sections/commit-workflow.ts"
)

echo "=== Checking old commit-policy strings are ABSENT ==="

COMMON_STALE_STRINGS=(
    "Only create commits when requested by the user"
    "NEVER commit changes unless the user explicitly asks"
    "Never commit unless explicitly requested"
    "Never commit unless asked"
    "If no active workflow calls for a commit, ask first"
)

PROMETHEUS_STALE_STRINGS=(
    "Do not commit automatically unless the user explicitly requests a commit"
)

for target in "${ALL_TARGETS[@]}"; do
    for old_str in "${COMMON_STALE_STRINGS[@]}"; do
        assert_file_or_skip "$target" assert_no_grep "$old_str" "$target"
    done
done

for target in "${PROMETHEUS_TARGETS[@]}"; do
    for old_str in "${PROMETHEUS_STALE_STRINGS[@]}"; do
        assert_file_or_skip "$target" assert_no_grep "$old_str" "$target"
    done
done

echo "=== Checking canonical replacement policy is PRESENT ==="

CANONICAL_POLICY="Git commits: follow the active git workflow"
GITMASTER_POLICY="Local commits are workflow-authorized"

for target in "${CANONICAL_POLICY_TARGETS[@]}"; do
    assert_file_or_skip "$target" assert_grep "$CANONICAL_POLICY" "$target"
done

for target in "${OMO_GITMASTER_TARGETS[@]}"; do
    assert_file_or_skip "$target" assert_grep "$GITMASTER_POLICY" "$target"
done

echo "=== Checking safety guardrails remain ==="

for target in "${SAFETY_TARGETS[@]}"; do
    if [[ ! -f "$target" ]]; then
        echo "SKIP: File not found (Task may not be complete yet): $target"
        FILES_SKIPPED=$((FILES_SKIPPED + 1))
        continue
    fi

    if grep -qE 'secret|credentials|auth' "$target"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "FAIL: Safety term 'secret/credentials/auth' not found in $target"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi

    if grep -qE 'push|force-push' "$target"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "FAIL: Safety term 'push/force-push' not found in $target"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi

    if grep -qE 'destructive' "$target"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "FAIL: Safety term 'destructive' not found in $target"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
done

echo "=== Checking installed OpenCode binary ==="

OPENCODE_BINARY="/home/ezotoff/.opencode/bin/opencode"

if [[ -f "$OPENCODE_BINARY" ]]; then
    for old_str in "${COMMON_STALE_STRINGS[@]}"; do
        if strings "$OPENCODE_BINARY" 2>/dev/null | grep -qF "$old_str"; then
            echo "FAIL: Old string found in binary $OPENCODE_BINARY: $old_str"
            TESTS_FAILED=$((TESTS_FAILED + 1))
        else
            TESTS_PASSED=$((TESTS_PASSED + 1))
        fi
    done
else
    echo "SKIP: Binary not found (may not be installed yet): $OPENCODE_BINARY"
    FILES_SKIPPED=$((FILES_SKIPPED + 1))
fi

echo ""
echo "=========================================="
echo "Commit Policy Patch Verification Summary"
echo "=========================================="
echo "Passed: $TESTS_PASSED"
echo "Failed: $TESTS_FAILED"
if [[ $FILES_SKIPPED -gt 0 ]]; then
    echo "Skipped: $FILES_SKIPPED (source files not yet available)"
fi
echo "=========================================="

if [[ $TESTS_FAILED -gt 0 ]]; then
    exit 1
fi

exit 0
