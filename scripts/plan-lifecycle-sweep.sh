#!/usr/bin/env bash
#
# plan-lifecycle-sweep.sh — flag stale plans needing disposition
#
# Plan: .omo/plans/workflow-standardization.md §4 ulw-plan bullet (W2.3).
#
# Flags plans under .omo/plans/ whose mtime is older than 7 days AND that
# lack an `## Execution Record` section:
#   needs-disposition: <path> (age Nd, no execution record)
#
# Flags only — NEVER writes, never deletes. Exit 0 always (it is a report);
# findings go to stdout.
#
# Usage:
#   plan-lifecycle-sweep.sh [<plans_dir>]
#     <plans_dir> defaults to ./.omo/plans (or script-relative repo root).
#
# Dependencies: bash >= 4.3, GNU or BSD stat. No network, no ports.

set -euo pipefail

default_plans_dir() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    printf '%s/.omo/plans' "$(dirname "$script_dir")"
}

PLANS_DIR="${1:-$(default_plans_dir)}"

# Missing dir → empty report, exit 0 (nothing to flag).
[[ -d "$PLANS_DIR" ]] || exit 0

mtime_epoch() {
    stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0
}

now="$(date -u +%s)"
threshold=$(( 7 * 24 * 3600 ))

for f in "$PLANS_DIR"/*.md; do
    [[ -f "$f" ]] || continue
    name="$(basename "$f")"
    [[ "$name" == "INDEX.md" ]] && continue
    [[ "$name" == *.reviews.md ]] && continue

    epoch="$(mtime_epoch "$f")"
    age=$(( now - epoch ))
    (( age > threshold )) || continue

    grep -qE '^## Execution Record' "$f" && continue

    printf 'needs-disposition: %s (age %dd, no execution record)\n' \
        "$f" $(( age / 86400 ))
done

exit 0
