#!/usr/bin/env bash
# Regression: opencode--tui-pinned-session-race fix must stay in the TUI source.
# The fix has two structural parts in packages/tui/src/context/local.tsx:
#   1. Startup read merge guard (state.pending → merge file pins into memory)
#   2. prune() as file-level read-modify-write (never writes in-memory snapshot)
# If either disappears (revert, bad reapply after upgrade), this test fails.
set -o errexit
source "$(cd "$(dirname "$0")/.." && pwd)/helpers.sh"
SRC="${PIN_RACE_SRC:-$HOME/src/opencode/packages/tui/src/context/local.tsx}"
assert_file_exists "$SRC"
assert_grep "async function prune" "$SRC"
# Merge-guard body: merges file pins into memory when a mutation predated the read
assert_grep "for (const id of fromFile)" "$SRC"
# RMW prune: writes back the disk content minus the deleted id only
assert_grep 'onDisk.filter((id) => id !== sessionID)' "$SRC"
# prune must no longer call save() (the stale-snapshot overwrite path)
if grep -qE '^\s*save\(\)' <(sed -n '/async function prune/,/^      }$/p' "$SRC"); then
    echo "FAIL: prune() still calls save() — stale in-memory overwrite path is back"
    exit 1
fi
exit 0
