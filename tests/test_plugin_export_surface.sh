#!/usr/bin/env bash

# Plugin export-surface tripwire
#
# OpenCode's plugin loader (getLegacyPlugins, packages/opencode/src/plugin/index.ts)
# rejects ANY module export that is not a function: "Plugin export is not a
# function". One non-function export disqualifies the whole module — the plugin
# silently goes dark while everything else keeps working.
#
# This bug class disabled git-safety.ts from 2026-08-06 (1100 load errors) and
# provider-connect-retry.mjs from 2026-08-18 (26 load errors), both via object
# exports added for test hooks.
#
# This test statically scans every plugin ENTRY module for non-function
# `export const|let|var` declarations. Support modules under subdirectories
# (e.g. configs/opencode/aspect-dynamics/*.mjs, plugins/worktree/*.ts) are
# libraries consumed by the entry modules, not loaded by OpenCode's plugin
# loader directly — non-function exports there are fine and not scanned.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

FAIL=0

check_surface() {
    local file="$1"
    # Flag export const/let/var whose initializer is clearly not a function:
    # object literal, array, string (any quote style), number, boolean, null,
    # or a `new` expression. awk bracket classes keep the quoting sane;
    # \x60 is a backtick, \047 a single quote — both written as escapes so
    # this script itself stays parseable.
    local matches
    matches=$(awk '
        /^export[ \t]+(const|let|var)[ \t]+[A-Za-z_$][A-Za-z0-9_$]*[ \t]*=[ \t]*([\{\["\x60\047]|[0-9]|true|false|null|new[ \t])/ {
            print FILENAME ":" FNR ":" $0
        }
    ' "$file" 2>/dev/null || true)
    if [[ -n "$matches" ]]; then
        echo "FAIL: $file has non-function module export(s) - the OpenCode plugin loader will reject the whole module:"
        echo "$matches"
        FAIL=1
    fi
}

shopt -s nullglob
for f in "$REPO_ROOT"/configs/opencode/*.mjs "$REPO_ROOT"/plugins/*.ts; do
    check_surface "$f"
done
shopt -u nullglob

if [[ "$FAIL" -gt 0 ]]; then
    echo ""
    echo "plugin export-surface check: FAIL"
    exit 1
fi

echo "plugin export-surface check: PASS (all entry modules export functions only)"
exit 0
