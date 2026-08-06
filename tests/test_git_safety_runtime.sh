#!/usr/bin/env bash

# Git-safety runtime harness — runs unit tests for the pure helpers
# exported by plugins/git-safety.ts (parseLeadingCd, resolveWorkdir,
# detectHistoryRewriteCommand).
#
# These run via `bun test` against tests/git-safety/harness.ts. The
# destructive-command strings live INSIDE the .ts file, not in any bash
# command — otherwise git-safety.ts would intercept the test invocation
# itself (a behaviour we explicitly verified during the A+B implementation:
# `bun -e '...git reset --hard...'` from a dirty tree was correctly blocked
# and auto-stashed).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HARNESS="$SCRIPT_DIR/git-safety/harness.ts"

if ! command -v bun >/dev/null 2>&1; then
    echo "SKIP: bun not installed (unit harness requires bun)"
    exit 0
fi

cd "$REPO_ROOT"
echo "Running: git-safety pure-helper unit tests (bun test)"
if bun test "$HARNESS" 2>&1; then
    echo "PASS: git-safety runtime harness"
    exit 0
else
    echo "FAIL: git-safety runtime harness"
    exit 1
fi
