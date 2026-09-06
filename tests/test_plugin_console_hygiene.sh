#!/usr/bin/env bash
# Static hygiene gate: repo-owned plugins must not write to console.
# Console output leaks into the TUI viewport, journald, and `opencode run
# --format json` streams (AGENTS.md plugin rule). Root cause of the
# 2026-09-06 stdout spam regression ("[skill-nudger] Plugin loaded" and
# aspect-dynamics info logs polluting every opencode run).
#
# Scope: config-layer plugins (configs/opencode/**/*.mjs) and top-level
# plugin entry files (plugins/*.ts). kdco-primitives/log-warn.ts is
# EXCLUDED by design — its console.warn fallback serves CLI contexts
# outside the TUI server process.
#
# Usage: bash tests/test_plugin_console_hygiene.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

fail=0
checked=0

check_file() {
  local f="$1"
  [ -f "$f" ] || return 0
  checked=$((checked + 1))
  # Strip //-comments and block-comment continuation lines, then look for console calls
  local hits
  hits=$(sed -e 's://.*$::' -e 's:^\s*\*.*$::' "$f" | grep -nE 'console\.(log|info|warn|error|debug)\s*\(' || true)
  if [ -n "$hits" ]; then
    echo "FAIL: console call in $f"
    echo "$hits" | sed 's/^/    /'
    fail=1
  fi
}

# Config-layer plugins and support modules
while IFS= read -r -d '' f; do
  check_file "$f"
done < <(find "$REPO_ROOT/configs/opencode" -name '*.mjs' -print0)

# Top-level plugin entry files (kdco-primitives excluded by design)
for f in \
  "$REPO_ROOT/plugins/agent-git-workflow.ts" \
  "$REPO_ROOT/plugins/auto-checkpoint.ts" \
  "$REPO_ROOT/plugins/clickable-links.ts" \
  "$REPO_ROOT/plugins/git-safety.ts" \
  "$REPO_ROOT/plugins/review-enforcer.ts" \
  "$REPO_ROOT/plugins/session-id.ts" \
  "$REPO_ROOT/plugins/session-info.ts" \
  "$REPO_ROOT/plugins/worktree.ts"; do
  check_file "$f"
done

if [ "$fail" -ne 0 ]; then
  echo ""
  echo "plugin-console-hygiene: FAIL ($checked files checked)"
  exit 1
fi

echo "PASS: no console output calls in $checked plugin files"
exit 0
