#!/usr/bin/env bash
# Regression 005a: verify-live-patches.sh requires ALL targets to match.
# Tests the fix for the silent-loss bug where the verifier returned APPLIED
# if ANY listed target matched, even when dist/index.js lost the marker.
#
# Scenario: patch lists both dist/index.js and a source .ts file.
# Both files contain the verification pattern → APPLIED.
set -o errexit
source "$(cd "$(dirname "$0")/.." && pwd)/helpers.sh"
SCRIPT="$(cd "$(dirname "$0")/../.." && pwd)/scripts/verify-live-patches.sh"
if [[ ! -f "$SCRIPT" ]]; then echo "FAIL: verify-live-patches.sh not found"; exit 1; fi

tmpdir="$(mktemp -d)"; trap 'rm -rf "$tmpdir"' EXIT

# Simulate an OMO runtime directory with dist/index.js + source .ts
mkdir -p "$tmpdir/runtime/dist" "$tmpdir/runtime/packages/omo-opencode/src/hooks/runtime-fallback"
echo 'source: retrySource, settleMs: 0, checkToolState: false, input: retryPromptInput' \
  > "$tmpdir/runtime/dist/index.js"
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

# Create a minimal opencode.json that points at the test runtime
cat > "$tmpdir/opencode.json" <<CONFIG
{"plugin": ["file://$tmpdir/runtime"]}
CONFIG

output="$(PATCH_DIR="$tmpdir" OPENCODE_CONFIG="$tmpdir/opencode.json" bash "$SCRIPT" 2>&1 || true)"
printf '%s\n' "$output" > "$tmpdir/output"

assert_grep "APPLIED.*runtime-fallback-checktoolstate" "$tmpdir/output"
echo "PASS: both targets match → APPLIED"
