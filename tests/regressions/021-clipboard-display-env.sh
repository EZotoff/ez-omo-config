#!/usr/bin/env bash
# Regression 021: clipboard plugins must work from display-less server processes.
#
# Bug (2026-09-12): /session-info (and /session-id) failed with the toast
# "Failed to copy to clipboard (exit 1). Is xclip installed?" although xclip
# was installed. Root cause: the plugins spawn `xclip -selection clipboard`
# inheriting the opencode serve process env. The interactive server runs as a
# systemd user unit (opencode-interactive.service), and systemd user managers
# do NOT inherit the desktop session's DISPLAY/XAUTHORITY. xclip exited 1 with
# "Error: Can't open display: (null)".
#
# Fix: plugins/kdco-primitives/clipboard.ts discovers a display (inherited
# DISPLAY first, then /tmp/.X11-unix sockets) plus XAUTHORITY candidates, and
# both plugins route clipboard writes through copyToClipboard().
#
# This test simulates the server env (DISPLAY stripped) and asserts the helper
# still copies; it also pins the plugins to the helper (no direct xclip spawns).
set -o errexit
source "$(cd "$(dirname "$0")/.." && pwd)/helpers.sh"

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
command -v bun >/dev/null 2>&1 || { echo "FAIL: bun not found (hard dependency of this config)"; exit 1; }
command -v xclip >/dev/null 2>&1 || { echo "SKIP: xclip not installed"; exit 0; }
if ! ls /tmp/.X11-unix/X* >/dev/null 2>&1; then
    echo "SKIP: no X11 sockets in /tmp/.X11-unix (headless machine)"
    exit 0
fi

# 1. Static: both plugins route clipboard writes through the shared helper.
assert_grep 'kdco-primitives/clipboard' "$REPO_ROOT/plugins/session-id.ts"
assert_grep 'kdco-primitives/clipboard' "$REPO_ROOT/plugins/session-info.ts"
assert_no_grep 'xclip -selection clipboard' "$REPO_ROOT/plugins/session-id.ts"
assert_no_grep 'xclip -selection clipboard' "$REPO_ROOT/plugins/session-info.ts"

# 2. Dynamic: helper copies successfully with DISPLAY/WAYLAND_DISPLAY/XAUTHORITY
#    stripped — the exact env shape of opencode-interactive.service.
PROBE="ez-omo-regression-021-$$"
if env -u DISPLAY -u WAYLAND_DISPLAY -u XAUTHORITY \
    CLIPBOARD_HELPER_PATH="$REPO_ROOT/plugins/kdco-primitives/clipboard.ts" \
    CLIPBOARD_PROBE="$PROBE" bun -e '
const { copyToClipboard } = await import(process.env.CLIPBOARD_HELPER_PATH)
const r = copyToClipboard(process.env.CLIPBOARD_PROBE)
if (!r.success) {
  console.error(`copy failed exit=${r.exitCode} stderr=${r.stderr}`)
  process.exit(1)
}
console.log(`copy ok exit=${r.exitCode}`)
'; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "FAIL: copyToClipboard failed without DISPLAY in env (see above)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# 3. Readback: the clipboard now holds the probe (xclip forks to serve the
#    selection, so poll briefly for the owner to be reachable).
DISPLAY_NUM="$(ls /tmp/.X11-unix | grep -oE '^X[0-9]+$' | head -1 | tr -d 'X')"
READBACK=""
for _ in 1 2 3 4 5; do
    READBACK="$(DISPLAY=":${DISPLAY_NUM}" timeout 5 xclip -selection clipboard -o 2>/dev/null || true)"
    [ "$READBACK" = "$PROBE" ] && break
    sleep 0.3
done
if [ "$READBACK" = "$PROBE" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "FAIL: clipboard readback mismatch: got '${READBACK}' want '${PROBE}'"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

if [[ $TESTS_FAILED -gt 0 ]]; then
    echo "FAILURE: clipboard display-env regression (see tests/regressions/021-clipboard-display-env.sh)"
    exit 1
fi
echo "PASS: clipboard copy works from a display-less environment"
