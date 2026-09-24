#!/usr/bin/env bash
#
# workorder-lint.sh — validate a --lite lane workorder (.omo/workorders/<slug>-<date>.md)
# against docs/workorders.md. Plan: .omo/plans/workflow-standardization.md W3.1 (TODO 11).
#
# Usage:
#   workorder-lint.sh <file>        validate one workorder (flags only, no writes)
#   workorder-lint.sh --template    print a skeleton workorder (passes this lint)
#
# Rules (docs/workorders.md §Required fields):
#   (a) `intent:` and `budget:` header lines present and non-empty.
#   (b) `status:` is `open` or `done`.
#   (c) `## Scope` section with >=1 listed file path.
#   (d) `## Teardown checklist` section with >=1 checklist item.
#   (e) A COMPLETED workorder (status: done, or any checked `- [x]` box) requires:
#         - a `## Teardown receipt` section containing either
#           `closeout.status: complete|degraded|failed` or
#           `episode-receipt: <dir> seq <n>`, AND
#         - every teardown checklist item checked (post-hoc drift review done).
#   (f) `## Escalation` section, if present: must be `none` or NAME a canonical
#       trigger (scope-drift | budget-2x | blocking-dependency). A named trigger
#       on a `status: done` workorder is a violation (escalated work stays open).
#
# HTML comment lines (<!-- -->) are ignored so examples/hints may live inline.
# Exit: 0 = pass, 1 = violations found, 2 = usage/IO error.
#
# No network, no ports, no writes.

set -euo pipefail

fail() { echo "workorder-lint: $*" >&2; exit 2; }

usage() {
    sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 2
}

template() {
    cat <<'EOF'
# Workorder: <slug>

intent: one sentence — what this workorder achieves and why
budget: 30m            # or: 2 files — the bound you commit to
status: open           # open | done

## Scope

- path/to/file1        # every file the workorder may touch
- path/to/file2

## Teardown checklist

- [ ] artifacts cleaned / temp files removed
- [ ] no stray ports, processes, or background jobs
- [ ] docs updated where the change is user-visible

## Escalation

none                    # scope-drift | budget-2x | blocking-dependency | none

## Teardown receipt

<!-- REQUIRED before status: done. Exactly one of: -->
<!-- closeout.status: complete -->
<!-- episode-receipt: .omo/episodes/<slug>/manifest.yaml seq <n> -->
EOF
}

if [[ "${1:-}" == "--template" ]]; then
    [[ $# -eq 1 ]] || usage
    template
    exit 0
fi

[[ $# -eq 1 ]] || usage
file="$1"
[[ -f "$file" ]] || fail "no such file: $file"

# Section body: heading line through the next `## ` heading or EOF,
# with full-line HTML comments stripped.
section_body() {
    awk -v sec="$2" '
        /^## / { insec = ($0 == "## " sec) ? 1 : 0; next }
        insec && /^[[:space:]]*<!--.*-->[[:space:]]*$/ { next }
        insec { print }
    ' "$1"
}

errors=0
flag() { echo "workorder: $file: $1"; errors=$((errors + 1)); }

# --- (a) intent / budget, (b) status ---
get_field() {
    sed -n "s/^$1:[[:space:]]*//p" "$file" | sed -n '/./{p;q}' | sed 's/[[:space:]]*#.*$//'
}

intent="$(get_field intent)"
budget="$(get_field budget)"
status="$(get_field status)"

[[ -n "$intent" ]] || flag "missing or empty 'intent:' line"
[[ -n "$budget" ]] || flag "missing or empty 'budget:' line"
[[ "$status" == "open" || "$status" == "done" ]] \
    || flag "status must be open or done (got: '${status:-missing}')"

# --- (c) scope files ---
scope="$(section_body "$file" "Scope" | grep -c '^[[:space:]]*-[[:space:]]*[^[:space:]]' || true)"
[[ "$scope" -ge 1 ]] || flag "'## Scope' section missing or lists no files"

# --- (d) teardown checklist ---
checklist="$(section_body "$file" "Teardown checklist")"
[[ -n "$(printf '%s\n' "$checklist" | grep -E '^[[:space:]]*- \[[ x]\]' || true)" ]] \
    || flag "'## Teardown checklist' section missing or has no checklist items"

# --- (e) completed workorder rules ---
completed=0
[[ "$status" == "done" ]] && completed=1
if printf '%s\n' "$checklist" | grep -q '^[[:space:]]*- \[x\]'; then
    completed=1
fi

if [[ $completed -eq 1 ]]; then
    receipt="$(section_body "$file" "Teardown receipt")"
    if ! printf '%s\n' "$receipt" | grep -Eq '^[[:space:]]*closeout\.status: (complete|degraded|failed)[[:space:]]*$' \
       && ! printf '%s\n' "$receipt" | grep -Eq '^[[:space:]]*episode-receipt: [^[:space:]]+ seq [0-9]+[[:space:]]*$'; then
        flag "completed workorder has no teardown receipt (need 'closeout.status: ...' or 'episode-receipt: <dir> seq <n>')"
    fi
    unchecked="$(printf '%s\n' "$checklist" | grep -c '^[[:space:]]*- \[ \]' || true)"
    [[ "$unchecked" -eq 0 ]] \
        || flag "completed workorder has $unchecked unchecked teardown checklist item(s) — post-hoc drift review incomplete"
fi

# --- (f) escalation triggers ---
esc="$(section_body "$file" "Escalation" | sed 's/[[:space:]]*#.*$//' | grep -v '^[[:space:]]*$' || true)"
if [[ -n "$esc" ]]; then
    if ! printf '%s\n' "$esc" | grep -Eq '(scope-drift|budget-2x|blocking-dependency)|^none$|^[[:space:]]*none[[:space:]]*$'; then
        flag "'## Escalation' does not name a canonical trigger (scope-drift | budget-2x | blocking-dependency) or 'none'"
    fi
    if printf '%s\n' "$esc" | grep -Eq '(scope-drift|budget-2x|blocking-dependency)' \
       && [[ "$status" == "done" ]]; then
        flag "escalated workorder (trigger named) must not be status: done — escalate to a full lane/episode"
    fi
fi

if [[ $errors -gt 0 ]]; then
    exit 1
fi
exit 0
