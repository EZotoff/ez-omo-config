#!/usr/bin/env bash
# Regression 017: resuming a completed background task while its session is
# busy must keep the task running — not roll it back to "completed".
#
# Bug (2026-08-30, ses_facae8e4affezS7URnSTmMXIbz, bg_c16e323d): a
# task(task_id=...) continuation landed while the child session was
# transiently active (nested-notification wake). The prompt-async-gate
# dropped the resume prompt ("active" status) and
# restoreTaskAfterSkippedResume rolled the task back to its terminal
# snapshot ("completed") + scheduled the 10-min cleanup sweeper. The
# continuation work still ran, but the child's eventual session.idle hit
# the `task.status !== "running"` guard in handleSessionIdleBackgroundEvent
# → no completion, no notifyParentSession → the parent waited forever for
# a notification that could never fire. Silent deadlock; only signal was
# "Removed completed task from memory" 10 minutes later.
#
# Fix (patch omo--resume-skip-keep-running, source commit 8b883adab on
# fix/custom-patches-v4.19.2): gate statuses "active"/"reserved" in
# restoreTaskAfterSkippedResume keep the task running (resume() already
# established the full running state before dispatch) and skip every
# rollback side effect. Bounded worst case = task-poller stale timeout
# (interrupt + notify), never a permanent deadlock.
set -euo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/helpers.sh"

# Resolve the live OMO install (newest versioned dir), overridable for CI.
OMO_INSTALL="${OMO_INSTALL:-$(ls -d "$HOME"/oh-my-openagent-v* 2>/dev/null | sort -V | tail -1)}"
if [[ -z "$OMO_INSTALL" || ! -d "$OMO_INSTALL" ]]; then
    echo "FAIL: no oh-my-openagent-v* install found under \$HOME (set OMO_INSTALL to override)"
    exit 1
fi
MANAGER="$OMO_INSTALL/packages/omo-opencode/src/features/background-agent/manager.ts"
DIST="$OMO_INSTALL/dist/index.js"

assert_file_exists "$MANAGER"
assert_file_exists "$DIST"
command -v bun >/dev/null 2>&1 || { echo "FAIL: bun not found (hard dependency of this config)"; exit 1; }

# Source marker: the keep-running branch exists in the patched source...
assert_grep "EZ-PATCH: resume-skip-keep-running" "$MANAGER"
assert_grep 'skippedStatus === "active" || skippedStatus === "reserved"' "$MANAGER"
# ...and the legacy unconditional rollback is no longer the only path: the
# branch must return before cleanupPendingByParent for busy-session skips.
assert_grep "keeping task running until next idle" "$MANAGER"

# Compiled runtime bundle carries the patch (this is what the server loads).
assert_grep "keeping task running until next idle" "$DIST"

# Behavioral pin: the two flipped tests must pass against the patched source.
if (cd "$OMO_INSTALL/packages/omo-opencode" && bun test src/features/background-agent/manager.test.ts -t "resume promptAsync gate state" >/dev/null 2>&1); then
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "FAIL: focused resume-skip tests failed (expected 2 pass, 0 fail)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

if [[ ${TESTS_FAILED:-0} -gt 0 ]]; then
    echo "FAILURE: resume-skip keep-running patch missing or broken in $OMO_INSTALL"
    exit 1
fi
echo "PASS: busy-session resume skips keep the task running (source + dist + behavioral tests)"
