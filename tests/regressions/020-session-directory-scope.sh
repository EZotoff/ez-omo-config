#!/usr/bin/env bash
# Regression: opencode--tui-session-directory-scope fix must stay in the TUI source.
# Two structural parts in packages/tui/src/context/sync.tsx:
#   1. sessionListQuery returns {} when the directory filter is enabled — with the
#      SDK's x-opencode-directory routing and no scope/path param, the server filters
#      the list to SessionTable.directory == attach dir (exact directory). The old
#      worktree/path-subtree query degraded to project-wide at repo roots and lumped
#      all non-git dirs into the global project bucket.
#   2. session.updated INSERTs from the daemon's unfiltered global /event stream are
#      dropped unless they originate from this TUI's own directory (foreign sessions
#      from other `oa` terminals / /tmp dirs used to materialize in the list).
# Plus the toggle wording marker in app.tsx (source of the binary verification_pattern).
set -o errexit
source "$(cd "$(dirname "$0")/.." && pwd)/helpers.sh"
SYNC_SRC="${SESSION_SCOPE_SYNC_SRC:-$HOME/src/opencode/packages/tui/src/context/sync.tsx}"
APP_SRC="${SESSION_SCOPE_APP_SRC:-$HOME/src/opencode/packages/tui/src/app.tsx}"
assert_file_exists "$SYNC_SRC"
assert_file_exists "$APP_SRC"
# Part 1: exact-directory query
QUERY_REGION=$(sed -n '/function sessionListQuery/,/^    }$/p' "$SYNC_SRC")
if ! grep -q 'return {}' <(echo "$QUERY_REGION"); then
    echo "FAIL: sessionListQuery no longer returns {} — exact-directory server filter is not engaged"
    exit 1
fi
if grep -q 'path.relative' <(echo "$QUERY_REGION"); then
    echo "FAIL: project-wide path-subtree query is back — foreign/project-wide sessions will reappear"
    exit 1
fi
# Part 2: event insert guard scoped to the session.updated case
GUARD_REGION=$(sed -n '/case "session.updated"/,/case "session.next.moved"/p' "$SYNC_SRC")
if ! grep -q 'directory !== sdk.directory' <(echo "$GUARD_REGION"); then
    echo "FAIL: session.updated lost the foreign-directory insert guard — cross-dir sessions will be injected again"
    exit 1
fi
# Part 3: toggle wording (also the patch entry's verification_pattern source)
assert_grep 'Limit session list to current directory' "$APP_SRC"
exit 0
