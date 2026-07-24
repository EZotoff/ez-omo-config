#!/usr/bin/env bash
set -o errexit
source "$(cd "$(dirname "$0")/.." && pwd)/helpers.sh"
SCRIPT="$(cd "$(dirname "$0")/../.." && pwd)/scripts/verify-live-patches.sh"
if [[ ! -f "$SCRIPT" ]]; then echo "FAIL: verify-live-patches.sh not found"; exit 1; fi
tmpdir="$(mktemp -d)"; trap 'rm -rf "$tmpdir"' EXIT
mkdir -p "$tmpdir/config-runtime" "$tmpdir/wrong-runtime"
printf 'PATCH_PRESENT\n' > "$tmpdir/config-runtime/file.ts"
cat > "$tmpdir/patch.md" <<PATCH
---
patch_id: "runtime-path-fixture"
dependency: "oh-my-openagent"
target_file: "file.ts"
target_install_path: "$tmpdir/wrong-runtime"
status: "active"
dep_version: "test"
verification_pattern: "PATCH_PRESENT"
---
PATCH
output="$(PATCH_DIR="$tmpdir" OMO_RUNTIME_PATH="$tmpdir/config-runtime" bash "$SCRIPT" 2>&1 || true)"
printf '%s\n' "$output" > "$tmpdir/output"
assert_no_grep "MISSING-TARGET.*runtime-path-fixture\|STALE.*runtime-path-fixture" "$tmpdir/output"
