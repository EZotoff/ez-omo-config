#!/usr/bin/env bash
set -o errexit
source "$(cd "$(dirname "$0")/.." && pwd)/helpers.sh"
SCRIPT="$(cd "$(dirname "$0")/../.." && pwd)/scripts/verify-live-patches.sh"
if [[ ! -f "$SCRIPT" ]]; then echo "FAIL: verify-live-patches.sh not found"; exit 1; fi
tmpdir="$(mktemp -d)"; trap 'rm -rf "$tmpdir"' EXIT
cat > "$tmpdir/retired.md" <<'PATCH'
---
patch_id: "retired-fixture"
dependency: "opencode"
target_file: "missing.ts"
target_install_path: "/nonexistent"
status: "retired"
dep_version: "test"
verification_pattern: "never"
---
PATCH
output="$(PATCH_DIR="$tmpdir" bash "$SCRIPT" 2>&1 || true)"
printf '%s\n' "$output" > "$tmpdir/output"
assert_no_grep "STALE.*retired-fixture\|retired-fixture.*STALE" "$tmpdir/output"
