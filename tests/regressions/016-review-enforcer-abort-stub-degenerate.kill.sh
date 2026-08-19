#!/usr/bin/env bash
# Kill-test 016: proves regression 016 detects the pre-fix plugin.
#
# Runs the marker checks and the behavioral harness against the preserved
# PRE-FIX backup (the exact file that exhibited the 2026-08-19 misfire).
set -o errexit
source "$(cd "$(dirname "$0")/.." && pwd)/helpers.sh"

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HARNESS="$REPO_ROOT/tests/review-enforcer/harness.ts"
BACKUP_DIR="${REVIEW_ENFORCER_BACKUP_DIR:-$HOME/.opencode/plugin/backups}"
BACKUP="$(ls -1 "$BACKUP_DIR"/review-enforcer.ts.pre-abort-gates.* 2>/dev/null | head -1)"

if [[ -z "$BACKUP" ]]; then
    echo "SKIP: no pre-abort-gates backup found in $BACKUP_DIR (kill-test needs the preserved pre-fix file)"
    exit 0
fi
echo "Using backup: $BACKUP"

# Pre-fix file must lack the guard markers...
assert_no_grep "isAbortStub" "$BACKUP"
assert_no_grep "isDegenerateOutput" "$BACKUP"
assert_no_grep "CONSULTATIVE_CATEGORIES" "$BACKUP"
if [[ $TESTS_FAILED -gt 0 ]]; then
    echo "FAILURE: pre-fix backup unexpectedly contains abort-gate markers"
    exit 1
fi

# ...and the behavioral harness must fail against it (exports missing).
KILL_TMP="$(mktemp -d)"
trap 'rm -rf "$KILL_TMP"' EXIT
cp "$BACKUP" "$KILL_TMP/pre-fix-plugin.ts"
assert_command_fails "harness abort vs pre-fix backup" env REVIEW_ENFORCER_MODULE="$KILL_TMP/pre-fix-plugin.ts" bun "$HARNESS" abort

if [[ $TESTS_FAILED -gt 0 ]]; then
    echo "FAILURE: kill-test 016 broken"
    exit 1
fi
echo "PROVED: regression 016 detects the pre-fix state (backup lacks guards; harness fails against it)"
