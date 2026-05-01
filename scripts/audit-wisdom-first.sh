#!/usr/bin/env bash
set -euo pipefail

# audit-wisdom-first.sh
# Validates that the repository contains no contradictory active-runtime statements
# about manifests or knowledge being canonical runtime stores.
#
# Exit 0 if all pass, exit 1 if any fail.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

FAILURES=0

echo "=== Wisdom-First Architecture Audit ==="
echo "Repo: $REPO_ROOT"
echo ""

# --------------------------------------------------------------------------
# 1. Banned phrases check
# --------------------------------------------------------------------------
echo "--- Checking for banned phrases ---"

BANNED_PATTERNS=(
  "manifest-first"
  "manifests are canonical"
  "knowledge is the primary"
  "authority-first via manifests"
  "canonical runtime values"
  "canonical runtime ranking"
  "canonical Wisdom store"
)

BANNED_FOUND=0
for pattern in "${BANNED_PATTERNS[@]}"; do
  matches=$(grep -ri "$pattern" \
    --exclude="audit-wisdom-first.sh" \
    --exclude="COMPATIBILITY-DEBT.md" \
    --exclude-dir=".git" \
    --exclude-dir=".sisyphus" \
    "$REPO_ROOT/docs/" \
    "$REPO_ROOT/skills/" \
    "$REPO_ROOT/scripts/" \
    "$REPO_ROOT/configs/oh-my-openagent/" \
    "$REPO_ROOT/commands/" \
    "$REPO_ROOT/README.md" \
    "$REPO_ROOT/AGENTS.md" \
    "$REPO_ROOT/MANIFEST.md" \
    2>/dev/null || true)

  if [[ -n "$matches" ]]; then
    echo "FAIL: Found banned phrase '$pattern':"
    echo "$matches" | while read -r line; do
      echo "  $line"
    done
    BANNED_FOUND=1
    FAILURES=$((FAILURES + 1))
  fi
done

if [[ "$BANNED_FOUND" -eq 0 ]]; then
  echo "PASS: No banned phrases found"
fi

echo ""

# --------------------------------------------------------------------------
# 2. Required phrases check (in active prompts and key docs)
# --------------------------------------------------------------------------
echo "--- Checking for required phrases ---"

REQUIRED_FOUND=0

# Check oh-my-openagent.json prompts for "Wisdom is the only runtime"
if grep -q "Wisdom is the only runtime" "$REPO_ROOT/configs/oh-my-openagent/oh-my-openagent.json"; then
  echo "PASS: 'Wisdom is the only runtime' found in oh-my-openagent.json prompts"
  REQUIRED_FOUND=1
else
  echo "FAIL: 'Wisdom is the only runtime' not found in oh-my-openagent.json prompts"
  FAILURES=$((FAILURES + 1))
fi

# Check skills/wisdom/SKILL.md for "Wisdom is the primary and only runtime"
if grep -q "primary and only runtime" "$REPO_ROOT/skills/wisdom/SKILL.md"; then
  echo "PASS: 'Wisdom is the primary and only runtime' found in skills/wisdom/SKILL.md"
  REQUIRED_FOUND=1
else
  echo "FAIL: 'Wisdom is the primary and only runtime' not found in skills/wisdom/SKILL.md"
  FAILURES=$((FAILURES + 1))
fi

# Check that no agent lists "knowledge" in its skills array
if grep -q '"knowledge"' "$REPO_ROOT/configs/oh-my-openagent/oh-my-openagent.json"; then
  echo "FAIL: 'knowledge' still found in oh-my-openagent.json agent skills arrays"
  FAILURES=$((FAILURES + 1))
else
  echo "PASS: No agent lists 'knowledge' in its skills array"
fi

echo ""

# --------------------------------------------------------------------------
# 3. COMPATIBILITY-DEBT.md exists and has deletion milestones
# --------------------------------------------------------------------------
echo "--- Checking COMPATIBILITY-DEBT.md ---"

DEBT_FILE="$REPO_ROOT/docs/COMPATIBILITY-DEBT.md"

if [[ ! -f "$DEBT_FILE" ]]; then
  echo "FAIL: docs/COMPATIBILITY-DEBT.md does not exist"
  FAILURES=$((FAILURES + 1))
else
  echo "PASS: docs/COMPATIBILITY-DEBT.md exists"

  if grep -q "Removal Milestone" "$DEBT_FILE"; then
    echo "PASS: Removal milestone section found"
  else
    echo "FAIL: No removal milestone section found"
    FAILURES=$((FAILURES + 1))
  fi

  if grep -q "Deletion criteria" "$DEBT_FILE"; then
    echo "PASS: Deletion criteria found"
  else
    echo "FAIL: No deletion criteria found"
    FAILURES=$((FAILURES + 1))
  fi

  if grep -q "knowledge-lookup.sh" "$DEBT_FILE" && \
     grep -q "knowledge-snapshot.sh" "$DEBT_FILE" && \
     grep -q "knowledge-promote.sh" "$DEBT_FILE"; then
    echo "PASS: All remaining shims documented"
  else
    echo "FAIL: Not all remaining shims documented"
    FAILURES=$((FAILURES + 1))
  fi
fi

echo ""

# --------------------------------------------------------------------------
# 4. Summary
# --------------------------------------------------------------------------
echo "=== Audit Summary ==="
if [[ "$FAILURES" -eq 0 ]]; then
  echo "PASS: All checks passed"
  exit 0
else
  echo "FAIL: $FAILURES check(s) failed"
  exit 1
fi
