#!/usr/bin/env bash
set -o errexit
source "$(cd "$(dirname "$0")/.." && pwd)/helpers.sh"
SCRIPT="$(cd "$(dirname "$0")/../.." && pwd)/scripts/verify-live-patches.sh"
if [[ ! -f "$SCRIPT" ]]; then echo "FAIL: verify-live-patches.sh not found"; exit 1; fi
output="$(bash "$SCRIPT" "/tmp/path with spaces/fake-binary" 2>&1 || true)"
tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
printf '%s\n' "$output" > "$tmp"
assert_no_grep "No such file or directory.*path with spaces\|command not found.*path with spaces" "$tmp"
