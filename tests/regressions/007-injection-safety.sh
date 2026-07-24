#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../helpers.sh"
SCRIPT="$(cd "$(dirname "$0")/../.." && pwd)/scripts/verify-live-patches.sh"

if [[ ! -f "$SCRIPT" ]]; then
    echo "FAIL: verify-live-patches.sh not found"
    exit 1
fi

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
mkdir -p "$TMP_ROOT/scripts" "$TMP_ROOT/.sisyphus/patches" "$TMP_ROOT/tree"
cp "$SCRIPT" "$TMP_ROOT/scripts/verify-live-patches.sh"
printf 'harmless target\n' >"$TMP_ROOT/tree/file.ts"
cat >"$TMP_ROOT/.sisyphus/patches/injection.md" <<PATCH
---
patch_id: "injection-safety-regression"
dependency: "opencode"
target_file: "file.ts"
target_install_path: "$TMP_ROOT/tree"
status: "active"
dep_version: "test"
verification_pattern: "__INJECTION_TEST__''', text); import os; os.system('echo PWNED'); #"
---
PATCH

bash "$TMP_ROOT/scripts/verify-live-patches.sh" --tree "$TMP_ROOT/tree" >"$TMP_ROOT/output" 2>&1 || true
assert_no_grep 'PWNED' "$TMP_ROOT/output" || true
if [[ $TESTS_FAILED -gt 0 ]]; then
    echo "FAIL: verification_pattern executed as Python source"
    exit 1
fi
exit 0
