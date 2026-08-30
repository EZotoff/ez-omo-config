#!/usr/bin/env bash
# Kill-test 017: proves regression 017 detects the pre-fix state.
#
# Uses the preserved pre-fix artifacts: the pre-patch source revision
# (git commit 8b883adab^ on fix/custom-patches-v4.19.2) and the pre-patch
# dist bundle (dist/index.js.pre-resume-skip-keep-running). If neither is
# available (fresh install, history rewritten), SKIP like kill-test 016.
set -euo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/helpers.sh"

OMO_INSTALL="${OMO_INSTALL:-$(ls -d "$HOME"/oh-my-openagent-v* 2>/dev/null | sort -V | tail -1)}"
if [[ -z "$OMO_INSTALL" || ! -d "$OMO_INSTALL" ]]; then
    echo "SKIP: no oh-my-openagent-v* install found under \$HOME"
    exit 0
fi
BACKUP_DIST="$OMO_INSTALL/dist/index.js.pre-resume-skip-keep-running"
PRE_FIX_COMMIT="8b883adab^"
MANAGER_REL="packages/omo-opencode/src/features/background-agent/manager.ts"

# At least one pre-fix artifact must exist, else the kill-test cannot run.
if [[ ! -f "$BACKUP_DIST" ]] && ! git -C "$OMO_INSTALL" cat-file -e "$PRE_FIX_COMMIT:$MANAGER_REL" 2>/dev/null; then
    echo "SKIP: no pre-fix artifacts (backup bundle or git history) found in $OMO_INSTALL"
    exit 0
fi

# Pre-fix dist bundle lacks the patch literal → the regression's dist-grep
# would fail against it.
if [[ -f "$BACKUP_DIST" ]]; then
    assert_no_grep "keeping task running until next idle" "$BACKUP_DIST"
    assert_no_grep "EZ-PATCH: resume-skip-keep-running" "$BACKUP_DIST"
fi

# Pre-fix source revision lacks the keep-running branch (and its guard) →
# the regression's source assertions would fail against it.
if git -C "$OMO_INSTALL" cat-file -e "$PRE_FIX_COMMIT:$MANAGER_REL" 2>/dev/null; then
    SRC_TMP="$(mktemp)"
    trap 'rm -f "$SRC_TMP"' EXIT
    git -C "$OMO_INSTALL" show "$PRE_FIX_COMMIT:$MANAGER_REL" > "$SRC_TMP"
    assert_no_grep "keeping task running until next idle" "$SRC_TMP"
    assert_no_grep 'skippedStatus === "active" || skippedStatus === "reserved"' "$SRC_TMP"
fi

if [[ ${TESTS_FAILED:-0} -gt 0 ]]; then
    echo "FAILURE: pre-fix artifacts unexpectedly contain resume-skip-keep-running markers"
    exit 1
fi
echo "PROVED: regression 017 detects the pre-fix state (keep-running markers absent from backup bundle and pre-patch source)"
