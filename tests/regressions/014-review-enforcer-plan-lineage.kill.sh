#!/usr/bin/env bash
# Kill-test 014: proves regression 014 detects the pre-fix plugin.
#
# Runs the marker checks and the behavioral harness against the preserved
# PRE-FIX backup (the exact file that exhibited the 2026-08-16 misfire).
# The unpatched file must lack the lineage gates and fail the harness —
# proving the regression test catches reintroduction.
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

# Pre-fix file must lack the gate markers...
assert_no_grep "sessionOwnsBoulder" "$BACKUP"
assert_no_grep "boulderStatusAllowsInjection" "$BACKUP"
if [[ $TESTS_FAILED -gt 0 ]]; then
    echo "FAILURE: pre-fix backup unexpectedly contains lineage gate markers"
    exit 1
fi

# ...and the behavioral harness must fail against it (exports missing).
# Copy to a .ts path so bun transpiles it regardless of the backup suffix.
KILL_TMP="$(mktemp -d)"
trap 'rm -rf "$KILL_TMP"' EXIT
cp "$BACKUP" "$KILL_TMP/pre-fix-plugin.ts"
assert_command_fails "harness lineage vs pre-fix backup" env REVIEW_ENFORCER_MODULE="$KILL_TMP/pre-fix-plugin.ts" bun "$HARNESS" lineage

if [[ $TESTS_FAILED -gt 0 ]]; then
    echo "FAILURE: kill-test 014 broken"
    exit 1
fi
echo "PROVED: regression 014 detects the pre-fix state (backup lacks gates; harness fails against it)"
