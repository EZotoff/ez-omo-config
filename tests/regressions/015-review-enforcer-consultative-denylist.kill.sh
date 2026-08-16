#!/usr/bin/env bash
# Kill-test 015: proves regression 015 detects the pre-fix plugin.
#
# Runs the marker checks and the behavioral harness against the preserved
# PRE-FIX backup. The unpatched file must lack the consultative denylist and
# fail the harness — proving the regression test catches reintroduction.
set -o errexit
source "$(cd "$(dirname "$0")/.." && pwd)/helpers.sh"

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HARNESS="$REPO_ROOT/tests/review-enforcer/harness.ts"
BACKUP_DIR="${REVIEW_ENFORCER_BACKUP_DIR:-$HOME/.opencode/plugin/backups}"
BACKUP="$(ls -1 "$BACKUP_DIR"/review-enforcer.ts.pre-session-gates.* 2>/dev/null | head -1)"

if [[ -z "$BACKUP" ]]; then
    echo "SKIP: no pre-session-gates backup found in $BACKUP_DIR (kill-test needs the preserved pre-fix file)"
    exit 0
fi
echo "Using backup: $BACKUP"

# Pre-fix file must lack the denylist markers...
assert_no_grep "CONSULTATIVE_SUBAGENT_TYPES" "$BACKUP"
assert_no_grep "isConsultativeDispatch" "$BACKUP"
if [[ $TESTS_FAILED -gt 0 ]]; then
    echo "FAILURE: pre-fix backup unexpectedly contains consultative gate markers"
    exit 1
fi

# ...and the behavioral harness must fail against it (export missing).
KILL_TMP="$(mktemp -d)"
trap 'rm -rf "$KILL_TMP"' EXIT
cp "$BACKUP" "$KILL_TMP/pre-fix-plugin.ts"
assert_command_fails "harness consultative vs pre-fix backup" env REVIEW_ENFORCER_MODULE="$KILL_TMP/pre-fix-plugin.ts" bun "$HARNESS" consultative

if [[ $TESTS_FAILED -gt 0 ]]; then
    echo "FAILURE: kill-test 015 broken"
    exit 1
fi
echo "PROVED: regression 015 detects the pre-fix state (backup lacks denylist; harness fails against it)"
