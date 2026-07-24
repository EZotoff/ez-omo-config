#!/usr/bin/env bash
set -o errexit
source "$(cd "$(dirname "$0")/.." && pwd)/helpers.sh"
SCRIPT="$(cd "$(dirname "$0")/../.." && pwd)/scripts/verify-live-patches.sh"
if [[ ! -f "$SCRIPT" ]]; then echo "FAIL: verify-live-patches.sh not found"; exit 1; fi
tmpdir="$(mktemp -d)"; trap 'rm -rf "$tmpdir"' EXIT
mkdir "$tmpdir/runtime"; touch "$tmpdir/runtime/file1.ts" "$tmpdir/runtime/file3.ts"
cat > "$tmpdir/patch.md" <<PATCH
---
patch_id: "multi-file-fixture"
dependency: "opencode"
target_file: "file1.ts,file2.ts,file3.ts"
target_install_path: "$tmpdir/runtime"
status: "active"
dep_version: "test"
verification_pattern: "anything"
---
PATCH
output="$(PATCH_DIR="$tmpdir" bash "$SCRIPT" 2>&1 || true)"
printf '%s\n' "$output" > "$tmpdir/output"
assert_grep "MISSING-TARGET.*multi-file-fixture" "$tmpdir/output"
