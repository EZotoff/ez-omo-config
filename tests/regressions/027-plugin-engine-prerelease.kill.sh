#!/usr/bin/env bash
# Kill-proof for 027-plugin-engine-prerelease.sh: strip the includePrerelease
# argument from a copy of shared.ts and prove the test detects it.
set -o errexit
tmpdir="$(mktemp -d)"; trap 'rm -rf "$tmpdir"' EXIT
SRC="$HOME/src/opencode/packages/opencode/src/plugin/shared.ts"
[[ -f "$SRC" ]] || { echo "SKIP: source not present"; exit 0; }
# Reintroduce the bug shape: drop the third satisfies argument.
sed 's/semver\.satisfies(opencodeVersion, range, { includePrerelease: true })/semver.satisfies(opencodeVersion, range)/' \
    "$SRC" > "$tmpdir/shared.ts"
TEST="$(cd "$(dirname "$0")" && pwd)/027-plugin-engine-prerelease.sh"
if PLUGIN_ENGINE_PRERELEASE_SRC="$tmpdir/shared.ts" bash "$TEST" >/dev/null 2>&1; then
    echo "FAIL: test passed against includePrerelease-stripped source — sentinel broken"
    exit 1
fi
echo "PROVED: plugin-engine-prerelease test detects reintroduced bug"
exit 0
