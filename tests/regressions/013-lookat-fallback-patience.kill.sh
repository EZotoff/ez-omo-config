#!/usr/bin/env bash
# Kill-test 013: proves regression 013 detects the unpatched dist.
#
# Runs the marker checks against the preserved PRE-PATCH backup (the exact
# file that exhibited the 2026-08-16 bug). The unpatched file must NOT carry
# the markers — proving the regression test catches patch loss.
set -o errexit
source "$(cd "$(dirname "$0")/.." && pwd)/helpers.sh"

OMO_DIST_DIR="${OMO_DIST_DIR:-$(dirname "${OMO_DIST:-/home/ezotoff/oh-my-openagent-v4.19.2/dist/index.js}")}"
BACKUP="$(ls -1 "$OMO_DIST_DIR"/index.js.pre-lookat-fallback-patience.* 2>/dev/null | head -1)"

if [[ -z "$BACKUP" ]]; then
  echo "SKIP: no pre-lookat-fallback-patience backup found in $OMO_DIST_DIR (kill-test needs the preserved pre-patch file)"
  exit 0
fi
echo "Using backup: $BACKUP"

if grep -q "LOOK_AT_FALLBACK_PATIENCE_MS = 60000" "$BACKUP" || \
   grep -q "runtime-fallback answer may still land" "$BACKUP"; then
  echo "FAIL: pre-patch backup already contains the patch markers — regression 013 could NOT detect patch loss"
  exit 1
fi

TESTS_PASSED=$((TESTS_PASSED + 1))
echo "PROVED: regression 013 detects the unpatched state (backup lacks all patch markers)"
