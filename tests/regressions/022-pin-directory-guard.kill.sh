#!/usr/bin/env bash
# Kill-proof for 022-pin-directory-guard.sh: strip the guard from a copy of
# dialog-session-list.tsx and prove the test detects the regression.
set -o errexit
tmpdir="$(mktemp -d)"; trap 'rm -rf "$tmpdir"' EXIT
SRC="$HOME/src/opencode/packages/tui/src/component/dialog-session-list.tsx"
[[ -f "$SRC" ]] || { echo "SKIP: source not present"; exit 0; }
# Reintroduce the bug shape: rescue path admits any fetched session, no
# directory check (pre-guard pin-window behavior).
sed -e 's/opencode--tui-pin-directory-guard/guard-removed/' \
    -e 's/if (foreignPin(session, id)) return \[\]/if (false) return []/' \
    -e 's/session\.directory !== sdk\.directory/session.directory !== session.directory/' \
    -e 's/kv\.get("session_directory_filter_enabled", true) \&\& !!sdk\.directory \&\&/false \&\&/' \
    "$SRC" > "$tmpdir/dialog-session-list.tsx"
TEST="$(cd "$(dirname "$0")" && pwd)/022-pin-directory-guard.sh"
if PIN_GUARD_SRC="$tmpdir/dialog-session-list.tsx" bash "$TEST" >/dev/null 2>&1; then
    echo "FAIL: test passed against unguarded source — sentinel broken"
    exit 1
fi
echo "PROVED: pin-directory-guard test detects reintroduced bug"
exit 0
