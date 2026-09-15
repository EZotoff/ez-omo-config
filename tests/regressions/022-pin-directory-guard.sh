#!/usr/bin/env bash
# Regression: opencode--tui-pin-directory-guard must stay in the TUI source.
# The guard lives in packages/tui/src/component/dialog-session-list.tsx and
# drops foreign-directory pinned sessions from the dialog's `extra` rescue path
# (fetchedPinned / synced fallback). Why: session.get() by ID is NOT
# directory-scoped server-side, so without the guard the pin-window patch's
# fetch-by-ID path re-leaks other projects' sessions into a directory-scoped
# TUI (regression found 2026-09-15; fix commit ed579472d on
# fix/tui-pin-directory-guard-v1.18.5).
set -o errexit
source "$(cd "$(dirname "$0")/.." && pwd)/helpers.sh"
SRC="${PIN_GUARD_SRC:-$HOME/src/opencode/packages/tui/src/component/dialog-session-list.tsx}"
assert_file_exists "$SRC"
# Guard sentinel comment (source-level structural pin)
assert_grep "opencode--tui-pin-directory-guard" "$SRC"
# The guard helper must exist and consult the filter kv + sdk directory
assert_grep 'kv.get("session_directory_filter_enabled", true)' "$SRC"
assert_grep "session.directory !== sdk.directory" "$SRC"
# The extra rescue path must actually invoke the guard before admitting a session
assert_grep "if (foreignPin(session, id)) return \[\]" "$SRC"
# Guard applies to the fetch-by-ID path, not the current session
assert_grep "id !== currentSessionID()" "$SRC"
exit 0
