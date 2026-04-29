#!/usr/bin/env bash
set -euo pipefail

# knowledge-snapshot.sh — DEPRECATED compatibility shim
# Reads ONLY from Wisdom store. Never reads manifests.
# Usage: knowledge-snapshot.sh [--help]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${HOME}/.sisyphus/scripts/knowledge-constants.sh" 2>/dev/null || source "${SCRIPT_DIR}/knowledge-constants.sh" || { echo "ERROR: Failed to source knowledge-constants.sh" >&2; exit 1; }
source "${SCRIPT_DIR}/wisdom-common.sh" || { echo "ERROR: Failed to source wisdom-common.sh" >&2; exit 1; }

printf '[DEPRECATION] knowledge-snapshot.sh is deprecated; use wisdom-search.sh directly\n' >&2

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    cat >&2 <<'EOF'
Usage: knowledge-snapshot.sh [--help]

Generates a bounded text summary of authoritative knowledge for agent
session orientation. Outputs to stdout.

Reads ONLY from Wisdom store (~/.sisyphus/wisdom/*.jsonl).

Sections:
  1. Wisdom (Canonical)  — all entries from wisdom JSONL
  2. Stale Warnings      — entries past their review_due date

Output is truncated to KNOWLEDGE_SNAPSHOT_CHAR_LIMIT (6000 chars).
EOF
    exit 0
fi

TODAY=$(date -u +%Y-%m-%d)

WISDOM_SECTION=""
STALE_SECTION=""

wisdom_raw=$("${SCRIPT_DIR}/wisdom-search.sh" "" --json --limit 1000 --scope all 2>/dev/null) || true

if [[ -n "$wisdom_raw" && "$wisdom_raw" != "[]" && "$wisdom_raw" != '"UNKNOWN"' ]]; then
    count=$(printf '%s' "$wisdom_raw" | jq 'length')

    for i in $(seq 0 $((count - 1))); do
        entry=$(printf '%s' "$wisdom_raw" | jq -c ".[$i]")

        w_id=$(printf '%s' "$entry" | jq -r '.id')
        w_body=$(printf '%s' "$entry" | jq -r '.body // ""')
        w_authority=$(printf '%s' "$entry" | jq -r '.authority // "candidate"')
        w_type=$(printf '%s' "$entry" | jq -r '.type // "unknown"')
        w_verified_at=$(printf '%s' "$entry" | jq -r '.verified_at // "unknown"')
        w_review_due=$(printf '%s' "$entry" | jq -r '.review_due // ""')
        w_status=$(printf '%s' "$entry" | jq -r '.status // "unknown"')

        body_display="$w_body"
        body_display=$(printf '%s' "$body_display" | sed 's/\\n/ /g' | sed 's/\\"/"/g')
        if [[ ${#body_display} -gt 120 ]]; then
            body_display="${body_display:0:117}..."
        fi

        WISDOM_SECTION+="- [${w_type}] ${body_display} (authority: ${w_authority}, verified: ${w_verified_at})"$'\n'

        if [[ -n "$w_review_due" && "$w_review_due" != "null" ]] && [[ "$w_review_due" < "$TODAY" || "$w_review_due" == "$TODAY" ]] && [[ "$w_status" != "stale" && "$w_status" != "superseded" && "$w_status" != "retracted" ]]; then
            STALE_SECTION+="- ⚠️ [${w_id}] review due ${w_review_due} (authority: ${w_authority})"$'\n'
        fi
    done
fi

OUTPUT="# Knowledge Snapshot (generated: ${TODAY})"$'\n'
OUTPUT+=$'\n'"### Wisdom (Canonical)"$'\n'
if [[ -n "$WISDOM_SECTION" ]]; then
    OUTPUT+="$WISDOM_SECTION"
else
    OUTPUT+="(none)"$'\n'
fi

OUTPUT+=$'\n'"## Stale Warnings"$'\n'
if [[ -n "$STALE_SECTION" ]]; then
    OUTPUT+="$STALE_SECTION"
else
    OUTPUT+="(none)"$'\n'
fi

if [[ ${#OUTPUT} -gt ${KNOWLEDGE_SNAPSHOT_CHAR_LIMIT} ]]; then
    STALE_LEN=${#STALE_SECTION}
    WISDOM_LEN=${#WISDOM_SECTION}

    if [[ ${#OUTPUT} -gt ${KNOWLEDGE_SNAPSHOT_CHAR_LIMIT} && -n "$STALE_SECTION" ]]; then
        STALE_SECTION=""
        OUTPUT="# Knowledge Snapshot (generated: ${TODAY})"$'\n'
        OUTPUT+=$'\n'"### Wisdom (Canonical)"$'\n'
        OUTPUT+="${WISDOM_SECTION:-"(none)"$'\n'}"
        OUTPUT+=$'\n'"## Stale Warnings"$'\n'"(truncated)"$'\n'
    fi

    if [[ ${#OUTPUT} -gt ${KNOWLEDGE_SNAPSHOT_CHAR_LIMIT} && -n "$WISDOM_SECTION" ]]; then
        WISDOM_SECTION=""
        OUTPUT="# Knowledge Snapshot (generated: ${TODAY})"$'\n'
        OUTPUT+=$'\n'"### Wisdom (Canonical)"$'\n'"(truncated)"$'\n'
        OUTPUT+=$'\n'"## Stale Warnings"$'\n'"(truncated)"$'\n'
    fi

    if [[ ${#OUTPUT} -gt ${KNOWLEDGE_SNAPSHOT_CHAR_LIMIT} ]]; then
        OUTPUT="${OUTPUT:0:${KNOWLEDGE_SNAPSHOT_CHAR_LIMIT}}"
    fi
fi

printf '%s' "$OUTPUT"
