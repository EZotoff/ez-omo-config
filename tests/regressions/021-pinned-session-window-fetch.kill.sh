#!/usr/bin/env bash
# Kill-proof for 021-pinned-session-window-fetch.sh: strip the fix markers from a
# copy of dialog-session-list.tsx and prove the test detects the regression.
set -o errexit
tmpdir="$(mktemp -d)"; trap 'rm -rf "$tmpdir"' EXIT
SRC="$HOME/src/opencode/packages/tui/src/component/dialog-session-list.tsx"
[[ -f "$SRC" ]] || { echo "SKIP: source not present"; exit 0; }
# Reintroduce the bug shape: rescue path falls back to the sync window only,
# no per-ID fetch machinery.
sed -e 's/synced.get(id) ?? fetchedPinned()\[id\]/synced.get(id)/' \
    -e 's/sdk.client.session.get({ sessionID: id })/sdk.client.session.list({})/' \
    -e 's/pinnedFetches/pinnedFetchesOld/' \
    "$SRC" > "$tmpdir/dialog-session-list.tsx"
TEST="$(cd "$(dirname "$0")" && pwd)/021-pinned-session-window-fetch.sh"
if PIN_WINDOW_SRC="$tmpdir/dialog-session-list.tsx" bash "$TEST" >/dev/null 2>&1; then
    echo "FAIL: test passed against unfixed source — sentinel broken"
    exit 1
fi
echo "PROVED: pinned-session-window test detects reintroduced bug"
exit 0
