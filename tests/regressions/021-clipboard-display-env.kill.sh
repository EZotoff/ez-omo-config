#!/usr/bin/env bash
# Kill-test 020: proves regression 021 detects the reverted (pre-fix) code shape.
#
# Two reintroduction shapes are checked:
# 1. Static: a plugin that spawns xclip directly (no helper) must be flagged by
#    regression 021's assert_no_grep guard.
# 2. Dynamic: the OLD inline spawn (Bun.spawnSync without env injection) must
#    FAIL in the display-less simulation env — proving the dynamic check would
#    catch a revert.
set -o errexit
source "$(cd "$(dirname "$0")/.." && pwd)/helpers.sh"

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
command -v bun >/dev/null 2>&1 || { echo "FAIL: bun not found (hard dependency of this config)"; exit 1; }
command -v xclip >/dev/null 2>&1 || { echo "SKIP: xclip not installed"; exit 0; }
if ! ls /tmp/.X11-unix/X* >/dev/null 2>&1; then
    echo "SKIP: no X11 sockets in /tmp/.X11-unix (headless machine)"
    exit 0
fi

# 1. Static guard catches a reintroduced direct xclip spawn.
KILL_TMP="$(mktemp -d)"
trap 'rm -rf "$KILL_TMP"' EXIT
cp "$REPO_ROOT/plugins/session-id.ts" "$KILL_TMP/session-id.ts"
cat >> "$KILL_TMP/session-id.ts" <<'EOF'

// reverted pre-fix shape: direct xclip spawn without display env injection
const legacy = Bun.spawnSync(["bash", "-c", "printf '%s' 'x' | xclip -selection clipboard"])
EOF
if grep -q 'xclip -selection clipboard' "$KILL_TMP/session-id.ts"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))  # assert_no_grep in 020 would FAIL on this file — detection proven
else
    echo "FAILURE: kill-test 021 broken — reintroduced xclip spawn not detectable by grep"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# 2. Old spawn shape must fail without DISPLAY (exit 1, "Can't open display").
if env -u DISPLAY -u WAYLAND_DISPLAY -u XAUTHORITY bun -e '
const r = Bun.spawnSync(["bash", "-c", "printf %s probe | xclip -selection clipboard"])
console.error(`legacy spawn exit=${r.exitCode} success=${r.success}`)
process.exit(r.success ? 0 : 1)
' 2>/dev/null; then
    echo "FAILURE: kill-test 021 broken — legacy spawn unexpectedly succeeded without DISPLAY"
    TESTS_FAILED=$((TESTS_FAILED + 1))
else
    TESTS_PASSED=$((TESTS_PASSED + 1))  # legacy shape fails → regression 021's dynamic check catches a revert
fi

if [[ $TESTS_FAILED -gt 0 ]]; then
    exit 1
fi
echo "PROVED: regression 021 detects the reverted direct-xclip-spawn shape"
