#!/usr/bin/env bash
# test_patch_entries.sh — schema-validate all active patch-tracker entries
#
# Enforces frontmatter completeness for rendering patches:
#   - target_file must be present
#   - rendering-path target_file (cli/cmd/run/, tui/src/routes/, server/routes/) requires surfaces field
#   - patches with surfaces require runtime_effective field
#
# This catches metadata destruction (e.g., a cutover commit that deletes the
# surfaces field or collapses a specific target_file to a generic value) BEFORE
# it reaches the live binary. The review-enforcer plugin consumes test output,
# so a SCHEMA-VIOLATION here blocks the merge.
#
# This is the structural gate described in AGENTS.md "Patch-Preservation Safety
# Infrastructure" — it makes the TEMPLATE.md schema load-bearing, not advisory.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=== Patch Entry Schema Validation ==="
echo "Checking all status:active entries in .sisyphus/patches/"
echo ""

if bash "$REPO_ROOT/scripts/verify-live-patches.sh" --schema-only; then
    echo ""
    echo "PASS: all active patch entries satisfy schema requirements"
    exit 0
else
    echo ""
    echo "FAIL: schema violations detected — see above"
    echo ""
    echo "Fix by adding the missing frontmatter fields to the flagged entries."
    echo "See .sisyphus/patches/TEMPLATE.md for required fields per patch type."
    exit 1
fi
