#!/usr/bin/env bash
#
# execution-record-lint.sh — lint plan Execution Records and reviews ledgers.
# Plan: .omo/plans/workflow-standardization.md W2.4 (TODO 9).
#
# Usage:
#   execution-record-lint.sh plan <file>       lint one plan file (strict rules)
#   execution-record-lint.sh plans [dir]       sweep a plans dir (default .omo/plans)
#   execution-record-lint.sh ledger <file>     validate a .reviews.md ledger
#
# Exit: 0 = pass, 1 = violations found, 2 = usage/IO error.
#
# Plan rules:
#   (a) A plan containing ANY checked checkbox (`- [x]` or `N. [x]`) must have
#       an `## Execution Record` section whose first non-empty line is
#       `Execution baseline: <sha>`.
#         - `plan` mode: sha must be a full 40-hex commit SHA (the W2 contract).
#         - `plans` sweep mode: legacy forms are tolerated so historical
#           plans are not retro-failed: short SHAs (7-40 hex) and trailing
#           annotations after the SHA (e.g. `(worktree plan/...)`). A plan
#           with checked boxes and NO Execution Record section is reported
#           as `needs-disposition` (advisory, matches the W2.3 lifecycle
#           sweep) and does not fail the sweep — only structurally broken
#           records fail.
#   (b) Every CHECKED F-box row (`^F[0-9]+\. [x]` anywhere in the plan) must
#       have a corresponding `F#<n>: APPROVE|REJECT` verdict line inside the
#       Execution Record section.
#   (c) Every `F#<n>: REJECT` line inside the Execution Record requires, on
#       a line STRICTLY AFTER the REJECT line, EITHER:
#         - a line mentioning the same `F#<n>` AND a severity tag
#           (CRITICAL|MAJOR|MINOR) with actionable finding text (same-line
#           severity on the REJECT line itself no longer satisfies — the
#           finding must exist as its own follow-up record), OR
#         - a later `F#<n>: APPROVE|RESOLVED` verdict-position line
#           (`F#<n>: APPROVE`, colon-space-verdict, e.g. 'F#1: APPROVE +
#           F#2: APPROVE — delta review' satisfies BOTH F#1 and F#2).
#           Prose like 'not APPROVED' does NOT match (word-boundary
#           anchored). In legacy sweep mode ONLY, the same-line narrative
#           resolution `F#<n>: REJECT ... (then|→|->) (APPROVE|RESOLVED|
#           closed|fixed)` and same-line severity are still accepted
#           (historical records).
#       An unresolved REJECT with no severity-tagged finding fails (W2 QA row:
#       "F-wave REJECT without actionable finding → lint fails the record").
#
# Ledger rule (d) — accepted format (canonical per docs/reviews.md):
#   A markdown file containing ONE ```json fenced block per review round
#   (machine-checkable); markdown prose between blocks is allowed for
#   context and is ignored. Each block is a single JSON object:
#     {
#       "verdict": "OKAY|REJECT|ESCALATE|OKAY-WITH-RISKS",
#       "round": <number>,
#       "budget": <object or string describing round budget usage>,
#       "plan_digest": "<sha>",
#       "findings": [
#         {"locator": "...", "severity": "...", "claim": "...",
#          "required_change": "...", "evidence": "...",
#          "blocking_rationale": "..."}
#       ],
#       "disposition": <string|object|null>,
#       "remaining_risks": <string|array|null>
#     }
#   Mechanical rules (docs/reviews.md §Budget and hard stop):
#     (d1) At least one fenced block is required; non-json fenced blocks
#          are ignored.
#     (d2) Round numbers must be monotonically 1..N in file order —
#          no gaps, no duplicates.
#     (d3) Any round numbered >= 5 must carry extension evidence: its
#          `budget` must be an OBJECT containing `extended: true` and a
#          non-empty `extension_evidence` (string or array).
#     (d4) Any round numbered > 6 fails (4+2 budget exceeded).
#     (d5) If the LAST round is numbered 6 and its verdict is REJECT,
#          the ledger fails — the terminal verdict at budget exhaustion
#          must be ESCALATE or OKAY-WITH-RISKS.
#     (d6) An unterminated (unclosed) final ```json fence is a named
#          lint failure.
#
# No network, no ports, no writes.

set -euo pipefail

fail() { echo "execution-record-lint: $*" >&2; exit 1; }

usage() {
    sed -n '2,60p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 2
}

[[ $# -ge 1 ]] || usage

# --- plan section extraction ---------------------------------------------
# Prints the `## Execution Record` section body (heading line through the next
# `## ` heading or EOF) to stdout.
section_body() {
    awk '
        /^## Execution Record/ { insec = 1; next }
        insec && /^## /       { insec = 0 }
        insec                 { print }
    ' "$1"
}

# --- rules (a)-(c) for a single file -------------------------------------
# $1 = plan file, $2 = mode (strict|legacy)
lint_plan_file() {
    local file="$1" mode="$2"
    local errors=0
    [[ -f "$file" ]] || { echo "plan: no such file: $file"; return 1; }

    local has_x=0
    grep -Eq '^[[:space:]]*(-|[0-9]+\.)[[:space:]]*\[x\]' "$file" && has_x=1 || true

    local body
    body="$(section_body "$file")"

    if [[ $has_x -eq 1 && -z "$body" ]]; then
        echo "plan: $file: checked boxes but no '## Execution Record' section"
        return 1
    fi

    # Plans without checked boxes and without a record section are out of scope.
    [[ -z "$body" ]] && return 0

    local rc=0

    # (a) baseline line: first non-empty line of the section
    local firstline sha_re='^Execution baseline: [0-9a-f]{40}[[:space:]]*$'
    # legacy sweep: short SHAs + trailing annotations (e.g. worktree notes)
    [[ "$mode" == "legacy" ]] && sha_re='^Execution baseline: [0-9a-f]{7,40}([[:space:]].*)?$'
    firstline="$(printf '%s\n' "$body" | sed -n '/./{p;q}')"
    if ! printf '%s' "$firstline" | grep -Eq "$sha_re"; then
        echo "plan: $file: Execution Record first line is not a baseline SHA: '$firstline'"
        rc=1
    fi

    # (b) each checked F-box has an F#n verdict line in the section
    local fnum
    while IFS= read -r fnum; do
        [[ -n "$fnum" ]] || continue
        if ! printf '%s\n' "$body" | grep -Eq "F#${fnum}: (APPROVE|REJECT)"; then
            echo "plan: $file: checked F-box F${fnum} has no 'F#${fnum}: APPROVE|REJECT' line in Execution Record"
            rc=1
        fi
    done < <(grep -Eo '^F[0-9]+\. \[x\]' "$file" | grep -Eo '[0-9]+' || true)

    # (c) resolution rules (see header): strict mode requires the severity
    # finding on a line STRICTLY AFTER the REJECT line and resolutions at
    # verdict position (`F#n: APPROVE`, word-boundary anchored); legacy
    # sweep mode also accepts same-line severity and the same-line
    # narrative resolution `F#n: REJECT ... (then|→|->) (APPROVE|RESOLVED|closed|fixed)`.
    local total reject_n
    total="$(printf '%s\n' "$body" | wc -l | tr -d ' ')"
    while IFS= read -r reject_n; do
        [[ -n "$reject_n" ]] || continue
        local i satisfied=0 line
        for ((i = 1; i <= total; i++)); do
            line="$(printf '%s\n' "$body" | sed -n "${i}p")"
            printf '%s' "$line" | grep -Eq "F#${reject_n}: REJECT" || continue
            # scan lines after the REJECT line (strict: strictly after;
            # legacy: starting at the REJECT line itself)
            local j later start
            if [[ "$mode" == "legacy" ]]; then start=$i; else start=$((i + 1)); fi
            for ((j = start; j <= total; j++)); do
                later="$(printf '%s\n' "$body" | sed -n "${j}p")"
                if printf '%s' "$later" | grep -Eq "F#${reject_n}" \
                    && printf '%s' "$later" | grep -Eq '\((CRITICAL|MAJOR|MINOR)\)|\b(CRITICAL|MAJOR|MINOR)\b'; then
                    satisfied=1; break
                fi
                local res_re="F#${reject_n}: (APPROVE|RESOLVED)\b"
                if [[ "$mode" == "legacy" ]]; then
                    # legacy: loose matcher incl. same-line narrative
                    # 'REJECT then closed/fixed' prose forms
                    res_re="F#${reject_n}:.*(APPROVE|RESOLVED|closed|fixed)"
                fi
                if printf '%s' "$later" | grep -Eq "$res_re"; then
                    satisfied=1; break
                fi
            done
            if [[ $satisfied -eq 0 ]]; then
                echo "plan: $file: F#${reject_n}: REJECT without a strictly-later severity-tagged finding (CRITICAL|MAJOR|MINOR) or a verdict-position 'F#${reject_n}: APPROVE' resolution"
                rc=1
            fi
        done
    done < <(printf '%s\n' "$body" | grep -Eo 'F#[0-9]+: REJECT' | grep -Eo '[0-9]+' | sort -u || true)

    return $rc
}

# --- sweep mode -----------------------------------------------------------
lint_plans_dir() {
    local dir="${1:-.omo/plans}"
    [[ -d "$dir" ]] || fail "plans: no such directory: $dir"
    local rc=0 f
    for f in "$dir"/*.md; do
        [[ -f "$f" ]] || continue
        case "$(basename "$f")" in *.reviews.md) continue ;; esac
        if ! grep -Eq '^[[:space:]]*(-|[0-9]+\.)[[:space:]]*\[x\]' "$f"; then
            continue # no progress checkboxes -> out of scope
        fi
        if ! section_body "$f" | grep -q .; then
            echo "sweep: $f: needs-disposition (checked boxes, no Execution Record)"
            continue
        fi
        lint_plan_file "$f" legacy || rc=1
    done
    return $rc
}

# --- ledger rule (d) ------------------------------------------------------
lint_ledger() {
    local file="$1"
    [[ -f "$file" ]] || { echo "ledger: no such file: $file"; return 1; }
    local tmp seqf
    tmp="$(mktemp)"
    seqf="$(mktemp)"
    trap 'rm -f "$tmp" "$seqf"' RETURN

    local rc=0

    # (d6) unterminated (unclosed) ```json fence is a named failure
    if ! awk '
        /^```json[[:space:]]*$/ { open = 1; next }
        /^```[[:space:]]*$/     { open = 0 }
        END { exit open ? 3 : 0 }
    ' "$file"; then
        echo "ledger: $file: unterminated json fenced block"
        rc=1
    fi

    # Extract each ```json fenced block into $tmp, one JSON doc per record
    # separated by \x1e (records can be multiline). Delimiter is emitted
    # AFTER each block so there is no leading empty record.
    awk '
        /^```json[[:space:]]*$/ { inblk = 1; next }
        /^```[[:space:]]*$/     { if (inblk) printf "\036"; inblk = 0; next }
        inblk                   { print }
    ' "$file" > "$tmp"

    if ! grep -q $'\x1e' "$tmp"; then
        echo "ledger: $file: no json fenced blocks found"
        return 1
    fi

    local idx=0 doc
    while IFS= read -r -d $'\x1e' doc; do
        idx=$((idx + 1))
        [[ -n "$doc" ]] || { echo "ledger: $file: block $idx is empty"; rc=1; continue; }
        if ! printf '%s' "$doc" | jq -e '
            type == "object"
            and (.verdict | IN("OKAY", "REJECT", "ESCALATE", "OKAY-WITH-RISKS"))
            and (.round | type == "number")
            and has("budget")
            and (.plan_digest | type == "string")
            and (.findings | type == "array")
            and (.findings | all(has("locator") and has("severity") and has("claim")
                                 and has("required_change") and has("evidence")
                                 and has("blocking_rationale")))
            and has("disposition")
            and has("remaining_risks")
            and (if .round >= 5 then
                    (.budget | type == "object")
                    and (.budget.extended == true)
                    and (.budget.extension_evidence |
                        if type == "string" then length > 0
                        elif type == "array" then length > 0
                        else false end)
                 else true end)
        ' >/dev/null 2>&1; then
            echo "ledger: $file: block $idx does not match the reviews-ledger schema"
            printf '%s\n' "$doc" | jq . >/dev/null 2>&1 \
                || echo "ledger: $file: block $idx is not valid JSON"
            rc=1
            continue
        fi
        printf '%s %s\n' "$(printf '%s' "$doc" | jq -r '.round')" \
                          "$(printf '%s' "$doc" | jq -r '.verdict')" >> "$seqf"
    done < "$tmp"

    # (d2) monotonic 1..N, (d4) round > 6, (d5) terminal REJECT at round 6
    if [[ -s "$seqf" ]]; then
        local expected=1 row r v last_r=0 last_v="" mono=1
        while read -r r v; do
            [[ "$r" == "$expected" ]] || mono=0
            expected=$((expected + 1))
            last_r="$r"; last_v="$v"
            if (( r > 6 )); then
                echo "ledger: $file: round $r exceeds the 4+2 budget (max 6)"
                rc=1
            fi
        done < "$seqf"
        if [[ $mono -eq 0 ]]; then
            echo "ledger: $file: rounds are not monotonically numbered 1..N (gap or duplicate)"
            rc=1
        fi
        if [[ "$last_r" == "6" && "$last_v" == "REJECT" ]]; then
            echo "ledger: $file: REJECT at budget exhaustion (last round 6 terminal verdict must be ESCALATE or OKAY-WITH-RISKS)"
            rc=1
        fi
    fi
    return $rc
}

case "$1" in
    plan)
        [[ $# -eq 2 ]] || usage
        lint_plan_file "$2" strict
        ;;
    plans)
        lint_plans_dir "${2:-}"
        ;;
    ledger)
        [[ $# -eq 2 ]] || usage
        lint_ledger "$2"
        ;;
    *)
        usage
        ;;
esac
