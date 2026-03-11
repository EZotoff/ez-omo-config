#!/usr/bin/env bash
set -euo pipefail

# wisdom-merge.sh — Merge 2+ wisdom entries into a single combined entry
# Usage: wisdom-merge.sh --ids ID1,ID2,... --scope SCOPE [OPTIONS]

source "$(dirname "$0")/wisdom-common.sh"

# --------------------------------------------------------------------------
# Help/usage
# --------------------------------------------------------------------------
usage() {
    cat >&2 <<'EOF'
wisdom-merge.sh — Merge 2+ wisdom entries into one combined entry

Usage: wisdom-merge.sh --ids ID1,ID2,... --scope SCOPE [OPTIONS]

Required:
  --ids IDS               Comma-separated entry IDs to merge (min 2)
  --scope SCOPE           Scope: system, project, plan

Options:
  --project-id ID         Project/plan identifier (required for project/plan scope)
  --body TEXT             Override merged body (default: concatenate all bodies)
  --type TYPE             Override type (default: first entry's type)
  --tags TAGS             Override tags (default: union of all tags, deduplicated)
  --dry-run               Show merged entry + what would be deleted, no changes
  -h, --help              Show this help message

Merge behavior:
  - Body: concatenated with "\n\n---\n\n" separator (unless --body override)
  - Tags: union of all tags, deduplicated (unless --tags override)
  - Type: first entry's type (unless --type override)
  - quality_score: max of all source scores
  - accessed: sum of all source accessed counts
  - source: "merged from: ID1, ID2, ..."
  - created: current ISO8601 timestamp

Exit codes:
  0  Merge successful
  1  Entry not found
  2  Bad arguments or validation error

Examples:
  # Merge two system entries
  wisdom-merge.sh --ids 20250304-1234-abcd,20250304-5678-efgh --scope system

  # Merge with overridden type and dry-run
  wisdom-merge.sh --ids ID1,ID2,ID3 --scope project --project-id myproj --type pattern --dry-run
EOF
}

# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------
main() {
    wisdom_require_jq

    local ids=""
    local scope=""
    local project_id=""
    local body_override=""
    local type_override=""
    local tags_override=""
    local dry_run=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage
                exit 0
                ;;
            --ids)
                ids="$2"
                shift 2
                ;;
            --scope)
                scope="$2"
                shift 2
                ;;
            --project-id)
                project_id="$2"
                shift 2
                ;;
            --body)
                body_override="$2"
                shift 2
                ;;
            --type)
                type_override="$2"
                shift 2
                ;;
            --tags)
                tags_override="$2"
                shift 2
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            *)
                wisdom_log ERROR "Unknown option: $1"
                usage
                exit 2
                ;;
        esac
    done

    if [[ -z "$ids" ]]; then
        wisdom_log ERROR "Missing required option: --ids"
        usage
        exit 2
    fi

    if [[ -z "$scope" ]]; then
        wisdom_log ERROR "Missing required option: --scope"
        usage
        exit 2
    fi

    if [[ "$scope" == "project" || "$scope" == "plan" ]] && [[ -z "$project_id" ]]; then
        wisdom_log ERROR "Scope '$scope' requires --project-id"
        usage
        exit 2
    fi

    local id_array
    IFS=',' read -ra id_array <<< "$ids"

    if [[ ${#id_array[@]} -lt 2 ]]; then
        wisdom_log ERROR "At least 2 IDs required for merge (got ${#id_array[@]})"
        exit 2
    fi

    local store_path
    store_path=$(wisdom_get_store_path "$scope" "$project_id") || exit 2

    if [[ ! -f "$store_path" ]]; then
        wisdom_log ERROR "Store file not found: $store_path"
        exit 1
    fi

    local entries_json=()
    local entry_json
    for eid in "${id_array[@]}"; do
        if ! entry_json=$(wisdom_read_entry "$eid" "$store_path"); then
            wisdom_log ERROR "Entry '$eid' not found in $store_path"
            exit 1
        fi
        entries_json+=("$entry_json")
    done

    wisdom_log INFO "Read ${#entries_json[@]} entries for merge"

    local merged_body
    if [[ -n "$body_override" ]]; then
        merged_body="$body_override"
    else
        merged_body=""
        local separator=$'\n\n---\n\n'
        local first=true
        for ej in "${entries_json[@]}"; do
            local entry_body
            entry_body=$(printf '%s' "$ej" | jq -r '.body')
            if [[ "$first" == true ]]; then
                merged_body="$entry_body"
                first=false
            else
                merged_body="${merged_body}${separator}${entry_body}"
            fi
        done
    fi

    local tags_json
    if [[ -n "$tags_override" ]]; then
        tags_json=$(printf '%s' "$tags_override" | jq -R 'split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0))')
    else
        local all_tags_input=""
        for ej in "${entries_json[@]}"; do
            local entry_tags
            entry_tags=$(printf '%s' "$ej" | jq -c '.tags // []')
            all_tags_input="${all_tags_input}${entry_tags}"$'\n'
        done
        tags_json=$(printf '%s' "$all_tags_input" | jq -s 'add | unique')
    fi

    local merged_type
    if [[ -n "$type_override" ]]; then
        merged_type="$type_override"
    else
        merged_type=$(printf '%s' "${entries_json[0]}" | jq -r '.type')
    fi

    local max_score=0
    for ej in "${entries_json[@]}"; do
        local s
        s=$(printf '%s' "$ej" | jq -r '.quality_score // 0')
        if [[ "$s" -gt "$max_score" ]]; then
            max_score="$s"
        fi
    done

    local total_accessed=0
    for ej in "${entries_json[@]}"; do
        local a
        a=$(printf '%s' "$ej" | jq -r '.accessed // 0')
        total_accessed=$((total_accessed + a))
    done

    local merged_source
    merged_source="merged from: $(IFS=', '; echo "${id_array[*]}")"

    local new_id
    new_id=$(wisdom_generate_id)
    local created
    created=$(date -u +%Y-%m-%dT%H:%M:%SZ)

     if ! wisdom_check_secret "$merged_body"; then
         wisdom_log ERROR "Merge blocked: secret detected in merged body"
         exit 3
     fi

     local merged_entry
     merged_entry=$(jq -nc \
         --arg id "$new_id" \
         --arg type "$merged_type" \
         --arg scope "$scope" \
         --argjson tags "$tags_json" \
         --arg body "$merged_body" \
        --arg created "$created" \
        --argjson accessed "$total_accessed" \
        --arg source "$merged_source" \
        --argjson quality_score "$max_score" \
        '{
            id: $id,
            type: $type,
            scope: $scope,
            tags: $tags,
            body: $body,
            created: $created,
            accessed: $accessed,
            last_accessed: "",
            source: $source,
            quality_score: $quality_score
        }')

    if ! wisdom_validate_jsonl_line "$merged_entry"; then
        wisdom_log ERROR "Generated merged entry failed validation"
        exit 2
    fi

    if [[ "$dry_run" == true ]]; then
        wisdom_log INFO "[DRY-RUN] Merged entry:"
        printf '%s\n' "$merged_entry" | jq . >&2
        wisdom_log INFO "[DRY-RUN] Would delete source entries:"
        for eid in "${id_array[@]}"; do
            wisdom_log INFO "  - $eid"
        done
        wisdom_log INFO "[DRY-RUN] No changes made"
        exit 0
    fi

    # SAFETY: write merged entry FIRST, then delete sources (failure leaves data intact)
    wisdom_log INFO "Writing merged entry $new_id..."
    if ! wisdom_append_entry "$merged_entry" "$store_path"; then
        wisdom_log ERROR "Failed to write merged entry to store"
        exit 1
    fi

    if ! wisdom_read_entry "$new_id" "$store_path" >/dev/null 2>&1; then
        wisdom_log ERROR "Verification failed: merged entry not found after write"
        exit 1
    fi

    local delete_failed=false
    for eid in "${id_array[@]}"; do
        if ! wisdom_remove_entry "$eid" "$store_path"; then
            wisdom_log ERROR "Failed to delete source entry '$eid'"
            delete_failed=true
        else
            wisdom_log INFO "Deleted source entry: $eid"
        fi
    done

    if [[ "$delete_failed" == true ]]; then
        wisdom_log ERROR "Some source entries could not be deleted (merged entry $new_id was created)"
        exit 1
    fi

    wisdom_log INFO "Merge complete: ${#id_array[@]} entries → $new_id"

    printf '%s\n' "$new_id"
    exit 0
}

# Run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
