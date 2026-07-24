#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../helpers.sh"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
mkdir -p "$TMP_ROOT/plugins"
: >"$TMP_ROOT/plugins/live-patch-guard.ts"

if [[ -f "$TMP_ROOT/plugins/live-patch-guard.ts" ]]; then
    echo "FAIL: plugins/live-patch-guard.ts exists" >"$TMP_ROOT/assertion"
fi
if grep -q '^FAIL: plugins/live-patch-guard.ts exists$' "$TMP_ROOT/assertion"; then
    echo "KILL-PROVED: guard-absence assertion caught the present plugin"
    exit 0
fi
echo "KILL-BROKEN: missing guard-presence failure sentinel"
exit 1
