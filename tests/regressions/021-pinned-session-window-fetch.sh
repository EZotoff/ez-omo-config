#!/usr/bin/env bash
# Regression: opencode--tui-pinned-session-window fix must stay in the TUI source.
# The fix lives in packages/tui/src/component/dialog-session-list.tsx:
#   1. fetchedPinned signal + per-ID fetch effect (session.get for pins outside
#      the browse/search/sync windows)
#   2. The sessions memo rescue path consults fetchedPinned:
#      `synced.get(id) ?? fetchedPinned()[id]`
# If either disappears (revert, bad reapply after upgrade), the Pinned section
# silently empties whenever list pressure pushes pinned sessions out of the
# newest-100 / 30-day sync windows (veran incident 2026-09-14).
set -o errexit
source "$(cd "$(dirname "$0")/.." && pwd)/helpers.sh"
SRC="${PIN_WINDOW_SRC:-$HOME/src/opencode/packages/tui/src/component/dialog-session-list.tsx}"
assert_file_exists "$SRC"
# Fetch machinery: per-ID session.get for missing pins
assert_grep "fetchSession" "$SRC"
assert_grep "sdk.client.session.get({ sessionID: id })" "$SRC"
# Guard: no unbounded refetch of dead/deleted pin IDs
assert_grep "pinnedFetches" "$SRC"
# Rescue path must consult the fetched map (the actual fix)
assert_grep 'synced.get(id) ?? fetchedPinned()\[id\]' "$SRC"
# Effect sources include the pinned list so newly added pins get fetched
assert_grep "local.session.pinned()" "$SRC"
exit 0
