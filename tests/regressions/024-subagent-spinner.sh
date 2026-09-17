#!/usr/bin/env bash
# Regression: opencode--tui-subagent-spinner must stay in the TUI source.
# The aggregation lives in packages/tui/src/component/dialog-session-list.tsx
# and marks a parent session "working" when any of its (hidden) child
# sub-agent sessions has status busy/retry — otherwise a parent running work
# through a background sub-agent shows no spinner in the Sessions dialog and
# looks inactive (fix on fix/tui-subagent-spinner-v1.18.5).
set -o errexit
source "$(cd "$(dirname "$0")/.." && pwd)/helpers.sh"
SRC="${SUBAGENT_SPINNER_SRC:-$HOME/src/opencode/packages/tui/src/component/dialog-session-list.tsx}"
assert_file_exists "$SRC"
# Patch sentinel comment (source-level structural pin)
assert_grep "opencode--tui-subagent-spinner" "$SRC"
# The child-status aggregation must exist and read the per-child status map
assert_grep 'sync.data.session_status?\.\[child.id\]' "$SRC"
assert_grep 'workingChildParents.add(child.parentID)' "$SRC"
# The aggregation must feed the spinner decision for parent rows
assert_grep 'workingChildParents.has(x.id)' "$SRC"
# The aggregation must union the roots-only browse list with the unfiltered sync
# list — children are excluded from browse/search by roots:true.
assert_grep 'for (const child of \[...sessions(), ...sync.data.session\])' "$SRC"
assert_grep 'seenChildren.has(child.id)' "$SRC"
exit 0
