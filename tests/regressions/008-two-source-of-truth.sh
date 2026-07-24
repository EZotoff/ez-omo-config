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
mkdir -p "$TMP_ROOT/scripts" "$TMP_ROOT/.sisyphus/patches" "$TMP_ROOT/configs/opencode" "$TMP_ROOT/path-A" "$TMP_ROOT/path-B"
cp "$SCRIPT" "$TMP_ROOT/scripts/verify-live-patches.sh"
printf 'AUTHORITATIVE_CONFIG_SENTINEL\n' >"$TMP_ROOT/path-A/file.ts"
printf 'wrong source\n' >"$TMP_ROOT/path-B/file.ts"
cat >"$TMP_ROOT/configs/opencode/opencode.json" <<JSON
{"plugin":["file://$TMP_ROOT/path-A"]}
JSON
cat >"$TMP_ROOT/.sisyphus/patches/two-sources.md" <<PATCH
---
patch_id: "two-source-of-truth-regression"
dependency: "oh-my-openagent"
target_file: "file.ts"
target_install_path: "$TMP_ROOT/path-B"
status: "active"
dep_version: "test"
verification_pattern: "AUTHORITATIVE_CONFIG_SENTINEL"
---
PATCH

bash "$TMP_ROOT/scripts/verify-live-patches.sh" >"$TMP_ROOT/output" 2>&1 || true
assert_grep 'APPLIED.*two-source-of-truth-regression\|two-source-of-truth-regression.*APPLIED' "$TMP_ROOT/output" || true
assert_no_grep "$TMP_ROOT/path-B" "$TMP_ROOT/output" || true
if [[ $TESTS_FAILED -gt 0 ]]; then
    echo "FAIL: target_install_path overwrote the config-resolved path"
    exit 1
fi
exit 0
