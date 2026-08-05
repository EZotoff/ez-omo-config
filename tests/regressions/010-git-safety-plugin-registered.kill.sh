#!/usr/bin/env bash
# Kill-proof for regression 010: proves the test fails when git-safety.ts
# is ABSENT from opencode.json#plugin.
#
# Strategy: build a minimal opencode.json that LACKS the git-safety entry
# (but retains valid JSON and one unrelated plugin), then run the same
# assert_json_contains_plugin check against it and confirm it produces the
# FAIL sentinel. This proves the test catches the regression it claims to.
set -o errexit
source "$(cd "$(dirname "$0")/.." && pwd)/helpers.sh"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

# Minimal opencode.json with NO git-safety.ts in the plugin array.
# This is the exact configuration that allowed the Veran incident.
cat >"$TMP_ROOT/opencode.json" <<'JSON'
{
  "enabled_providers": ["google"],
  "plugin": [
    "./provider-connect-retry.mjs",
    "../../.opencode/plugin/clickable-links.ts",
    "../../.opencode/plugin/session-id.ts"
  ]
}
JSON

# Pre-create a stub plugins/git-safety.ts so the file-exists assertion
# would pass — we want to isolate the registration check, not the
# file-existence check.
mkdir -p "$TMP_ROOT/plugins"
cat >"$TMP_ROOT/plugins/git-safety.ts" <<'TS'
export const GitSafetyPlugin = async () => ({ tool: {}, "tool.execute.before": async () => {} })
const PATTERN = /git\s+clean\b.*(-[a-zA-Z]*f|--force)/
TS

REPO_ROOT_BACKUP="${REPO_ROOT:-}"
REPO_ROOT="$TMP_ROOT"
export REPO_ROOT

# Run the registration check; expect it to FAIL (the plugin is absent).
if assert_json_contains_plugin "$TMP_ROOT/opencode.json" "git-safety.ts" >/dev/null 2>&1; then
    echo "KILL-BROKEN: assert_json_contains_plugin passed despite git-safety.ts being absent"
    exit 1
fi

echo "KILL-PROVED: registration check correctly fails when git-safety.ts is missing from opencode.json#plugin"
exit 0
