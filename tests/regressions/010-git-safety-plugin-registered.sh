#!/usr/bin/env bash
# Regression 010: git-safety.ts MUST be registered in opencode.json#plugin
#
# Bug fixed 2026-08-03: plugins/git-safety.ts was installed at
# ~/.opencode/plugin/git-safety.ts (symlinked from the repo) but was NOT
# listed in the opencode.json plugin array. Per AGENTS.md, plugins in
# ~/.opencode/plugin/*.ts are auto-loaded by OpenCode at startup, BUT
# command-pipeline interception (tool.execute.before hooks) only works for
# plugins registered in opencode.json#plugin. The git-safety plugin's
# entire purpose is tool.execute.before interception — so the guard was
# silently inert for the whole time it was "installed". A parallel session
# ran `git clean -fd` + a tracked-file reverter and wiped a sibling
# session's uncommitted work (Veran ses_0372179c6ffedu9tFDNzHT91aB).
#
# This test guards against silent drift back to "file installed but not
# registered" — the exact evidence-state gap (live_file_installed without
# active_config_registered) that made the original failure invisible.
set -o errexit
source "$(cd "$(dirname "$0")/.." && pwd)/helpers.sh"
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OPENCODE_JSON="$REPO_ROOT/configs/opencode/opencode.json"
PLUGIN_FILE="$REPO_ROOT/plugins/git-safety.ts"

[[ -f "$OPENCODE_JSON" ]] || { echo "FAIL: opencode.json not found at $OPENCODE_JSON"; exit 1; }
[[ -f "$PLUGIN_FILE" ]]   || { echo "FAIL: plugins/git-safety.ts not found at $PLUGIN_FILE"; exit 1; }

# 1. The plugin file must exist in the repo (sanity).
assert_file_exists "$PLUGIN_FILE"

# 2. The plugin MUST appear in the opencode.json plugin array — not just on disk.
assert_json_contains_plugin "$OPENCODE_JSON" "git-safety.ts"

# 3. The hook that does the actual interception MUST be present in the source.
#    If a future refactor removes tool.execute.before, the registration alone
#    is theatre — same class of silent failure as the original bug.
assert_grep 'tool.execute.before' "$PLUGIN_FILE"

# 4. The git clean pattern MUST be present. The original incident was a
#    `git clean -fd` that wiped untracked work; if this pattern is removed,
#    the guard no longer covers the exact case it was built for.
assert_grep 'git.clean' "$PLUGIN_FILE"

[[ "$TESTS_FAILED" -gt 0 ]] && { echo "FAIL: git-safety registration check(s) failed"; exit 1; }
echo "PASS: git-safety.ts registered in opencode.json#plugin and interception hook present"
exit 0
