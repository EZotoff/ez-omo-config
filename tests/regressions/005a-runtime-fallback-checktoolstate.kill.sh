#!/usr/bin/env bash
# Kill-test 005a: proves the verifier detects STALE when one target loses
# the marker (the silent-loss scenario from the 2026-07-23 incident).
#
# Scenario: dist/index.js is rebuilt WITHOUT the patch marker, but the
# source .ts file still has it. The OLD verifier returned APPLIED (bug).
# The FIXED verifier must return STALE.
set -o errexit
source "$(cd "$(dirname "$0")/.." && pwd)/helpers.sh"
SCRIPT="$(cd "$(dirname "$0")/../.." && pwd)/scripts/verify-live-patches.sh"
if [[ ! -f "$SCRIPT" ]]; then echo "FAIL: verify-live-patches.sh not found"; exit 1; fi

tmpdir="$(mktemp -d)"; trap 'rm -rf "$tmpdir"' EXIT

mkdir -p "$tmpdir/runtime/dist" "$tmpdir/runtime/packages/omo-opencode/src/hooks/runtime-fallback"

# dist/index.js LOST the marker (rebuilt without the patch)
echo 'source: retrySource, settleMs: 0, input: retryPromptInput' \
  > "$tmpdir/runtime/dist/index.js"

# source .ts STILL has the marker
echo 'checkToolState: false' \
  > "$tmpdir/runtime/packages/omo-opencode/src/hooks/runtime-fallback/auto-retry-dispatch.ts"

cat > "$tmpdir/patch.md" <<PATCH
---
patch_id: "runtime-fallback-checktoolstate"
dependency: "oh-my-openagent"
target_file: "dist/index.js, packages/omo-opencode/src/hooks/runtime-fallback/auto-retry-dispatch.ts"
target_install_path: "$tmpdir/runtime"
status: "active"
dep_version: "test"
verification_pattern: "checkToolState: false"
---
PATCH

cat > "$tmpdir/opencode.json" <<CONFIG
{"plugin": ["file://$tmpdir/runtime"]}
CONFIG

output="$(PATCH_DIR="$tmpdir" OPENCODE_CONFIG="$tmpdir/opencode.json" bash "$SCRIPT" 2>&1 || true)"
printf '%s\n' "$output" > "$tmpdir/output"

# The FIXED verifier must report STALE (not APPLIED) because dist/index.js
# lost the marker even though the source file still has it.
assert_grep "STALE.*runtime-fallback-checktoolstate" "$tmpdir/output"
echo "PROVED: silent-loss detected (STALE when dist marker missing)"
