#!/usr/bin/env bash
set -euo pipefail

# wisdom-edit.sh — Edit individual fields of a wisdom entry by ID
# Usage: wisdom-edit.sh ID --scope SCOPE [--project-id PROJECT] [edit-flags] [--dry-run]

# Source common functions
source "$(dirname "$0")/wisdom-common.sh"
wisdom_init_observability "$(basename "$0")"

_WISDOM_EDIT_START_MS=$(date +%s%3N 2>/dev/null || echo "")
_WISDOM_EDIT_RECORD_ID=""
_WISDOM_EDIT_SCOPE=""
_WISDOM_EDIT_PROJECT_ID=""
_WISDOM_EDIT_DRY_RUN="false"
_WISDOM_EDIT_CHANGED_FIELDS='[]'
_WISDOM_EDIT_AUTHORITY_BEFORE=""
_WISDOM_EDIT_AUTHORITY_AFTER=""

_wisdom_edit_emit_observability() {
    local rc=$?
    local status="ok"
    [[ "$rc" -ne 0 ]] && status="error"

    local duration_ms_json="null"
    if [[ -n "${_WISDOM_EDIT_START_MS:-}" ]]; then
        local now_ms
        now_ms=$(date +%s%3N 2>/dev/null || echo "")
        if [[ -n "$now_ms" ]]; then
            duration_ms_json=$((now_ms - _WISDOM_EDIT_START_MS))
        fi
    fi

    local payload='{}'
    payload=$(jq -nc \
        --arg record_id "${_WISDOM_EDIT_RECORD_ID:-}" \
        --arg scope "${_WISDOM_EDIT_SCOPE:-}" \
        --arg project_id "${_WISDOM_EDIT_PROJECT_ID:-}" \
        --arg dry_run "${_WISDOM_EDIT_DRY_RUN:-false}" \
        --arg authority_before "${_WISDOM_EDIT_AUTHORITY_BEFORE:-}" \
        --arg authority_after "${_WISDOM_EDIT_AUTHORITY_AFTER:-}" \
        --arg changed_fields_json "${_WISDOM_EDIT_CHANGED_FIELDS:-[]}" \
        --argjson duration_ms "$duration_ms_json" \
        '{
            record_id: (if $record_id == "" then null else $record_id end),
            scope: (if $scope == "" then null else $scope end),
            project_id: (if $project_id == "" then null else $project_id end),
            dry_run: ($dry_run == "true"),
            changed_fields: (($changed_fields_json | fromjson?) // []),
            authority_before: (if $authority_before == "" then null else $authority_before end),
            authority_after: (if $authority_after == "" then null else $authority_after end),
            duration_ms: $duration_ms
        }' 2>/dev/null) || payload='{}'

    wisdom_emit_event "wisdom.lifecycle.edit" "$status" "$payload"

    if [[ -n "${_WISDOM_EDIT_AUTHORITY_BEFORE:-}" && -n "${_WISDOM_EDIT_AUTHORITY_AFTER:-}" && "${_WISDOM_EDIT_AUTHORITY_BEFORE}" != "${_WISDOM_EDIT_AUTHORITY_AFTER}" ]]; then
        local authority_payload='{}'
        authority_payload=$(jq -nc \
            --arg record_id "${_WISDOM_EDIT_RECORD_ID:-}" \
            --arg scope "${_WISDOM_EDIT_SCOPE:-}" \
            --arg project_id "${_WISDOM_EDIT_PROJECT_ID:-}" \
            --arg authority_before "${_WISDOM_EDIT_AUTHORITY_BEFORE}" \
            --arg authority_after "${_WISDOM_EDIT_AUTHORITY_AFTER}" \
            --arg dry_run "${_WISDOM_EDIT_DRY_RUN:-false}" \
            --argjson duration_ms "$duration_ms_json" \
            '{
                record_id: (if $record_id == "" then null else $record_id end),
                scope: (if $scope == "" then null else $scope end),
                project_id: (if $project_id == "" then null else $project_id end),
                authority_before: $authority_before,
                authority_after: $authority_after,
                dry_run: ($dry_run == "true"),
                duration_ms: $duration_ms
            }' 2>/dev/null) || authority_payload='{}'
        wisdom_emit_event "wisdom.lifecycle.authority_change" "$status" "$authority_payload"
    fi
}

trap _wisdom_edit_emit_observability EXIT

# --------------------------------------------------------------------------
# Helper functions
# --------------------------------------------------------------------------

usage() {
    cat <<EOF
wisdom-edit.sh — Edit individual fields of a wisdom entry by ID

Usage: $0 [--id] ID --scope SCOPE [--project-id PROJECT] [edit-flags] [--dry-run]

Required arguments:
  ID                        Entry ID to edit
  --id                      Flag prefix for entry ID (optional)
  --scope SCOPE             Scope of the entry (system, project, plan)
  --project-id PROJECT      Project ID (required for project/plan scope)

Edit flags (at least one required):
  --set-body "new body"     Replace the body content
  --set-type "new type"     Change the entry type
  --set-tags "tag1,tag2"    Replace all tags (comma-separated)
  --add-tags "tag3,tag4"    Append tags to existing (comma-separated)
  --set-score N             Set quality_score (integer)
  --set-authority LEVEL     Set authority level: candidate|verified|published
  --set-status STATUS       Set status: active|stale|superseded|retracted
  --set-provenance VALUE    Set provenance: closeout|nomination|manual|manifest-import|migration|publish-export|compat-shim
  --set-origin-session ID   Set origin session ID string
  --set-superseded-by ID    Mark entry as superseded by another entry ID
  --set-contradicts ID      Add a Wisdom ID to the contradicts array
  --set-verified-at ISO     Set verification timestamp (ISO-8601)
  --set-review-due ISO      Set review due timestamp (ISO-8601)

Options:
  --dry-run                 Show before/after changes without writing
  -h, --help                Show this help message

Exit codes:
  0  Entry updated (or dry-run successful)
  1  Entry not found
  2  Bad arguments (missing required, invalid values)
  3  Secret detected in new body content

Examples:
  $0 20250304-123456-abcd --scope system --set-type pattern --set-tags "rust,build"
  $0 --id 20250304-123456-abcd --scope system --set-type pattern --set-tags "rust,build"
  $0 20250304-123456-abcd --scope project --project-id myproj --add-tags "api" --dry-run
EOF
}

# Parse comma-separated tags into JSON array
parse_tags_to_json() {
    local tags_str="$1"
    local tags_json="[]"
    
    if [[ -n "$tags_str" ]]; then
        # Split by comma, trim whitespace, wrap each in quotes
        tags_json=$(echo "$tags_str" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | jq -R . | jq -s .)
    fi
    
    echo "$tags_json"
}

# Validate type against WISDOM_VALID_TYPES
validate_type() {
    local type="$1"
    local valid=false
    
    for t in "${WISDOM_VALID_TYPES[@]}"; do
        if [[ "$type" == "$t" ]]; then
            valid=true
            break
        fi
    done
    
    if [[ "$valid" == false ]]; then
        echo "Error: invalid type '$type' (valid: ${WISDOM_VALID_TYPES[*]})" >&2
        return 1
    fi
    return 0
}

validate_enum_from_array() {
    local value="$1"
    local field_name="$2"
    local valid_values_name="$3"
    local -n valid_values_ref="$valid_values_name"
    local valid=false
    local candidate

    for candidate in "${valid_values_ref[@]}"; do
        if [[ "$value" == "$candidate" ]]; then
            valid=true
            break
        fi
    done

    if [[ "$valid" == false ]]; then
        echo "Error: invalid ${field_name} '$value' (valid: ${valid_values_ref[*]})" >&2
        return 1
    fi

    return 0
}

# Validate score is a number
validate_score() {
    local score="$1"
    
    if ! [[ "$score" =~ ^[0-9]+$ ]]; then
        echo "Error: score must be a positive integer" >&2
        return 1
    fi
    return 0
}

# --------------------------------------------------------------------------
# Main script
# --------------------------------------------------------------------------

main() {
    # Check for jq
    wisdom_require_jq || return 2
    
    # Parse arguments
    local entry_id=""
    local scope=""
    local project_id=""
    local dry_run=false
    local set_body=""
    local set_type=""
    local set_tags=""
    local add_tags=""
    local set_score=""
    local set_authority=""
    local set_status=""
    local set_provenance=""
    local set_origin_session=""
    local set_superseded_by=""
    local set_contradicts=""
    local set_verified_at=""
    local set_review_due=""
    local -a changed_fields=()
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage
                return 0
                ;;
            --id)
                entry_id="$2"
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
            --set-body)
                set_body="$2"
                shift 2
                ;;
            --set-type)
                set_type="$2"
                shift 2
                ;;
            --set-tags)
                set_tags="$2"
                shift 2
                ;;
            --add-tags)
                add_tags="$2"
                shift 2
                ;;
            --set-score)
                set_score="$2"
                shift 2
                ;;
            --set-authority)
                set_authority="$2"
                shift 2
                ;;
            --set-status)
                set_status="$2"
                shift 2
                ;;
            --set-provenance)
                set_provenance="$2"
                shift 2
                ;;
            --set-origin-session)
                set_origin_session="$2"
                shift 2
                ;;
            --set-superseded-by)
                set_superseded_by="$2"
                shift 2
                ;;
            --set-contradicts)
                set_contradicts="$2"
                shift 2
                ;;
            --set-verified-at)
                set_verified_at="$2"
                shift 2
                ;;
            --set-review-due)
                set_review_due="$2"
                shift 2
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            *)
                if [[ -z "$entry_id" ]]; then
                    entry_id="$1"
                    shift
                else
                    echo "Error: unexpected argument '$1'" >&2
                    usage >&2
                    return 2
                fi
                ;;
        esac
    done
    
    # Validate required arguments
    if [[ -z "$entry_id" ]]; then
        echo "Error: entry ID is required" >&2
        usage >&2
        return 2
    fi
    
    if [[ -z "$scope" ]]; then
        echo "Error: --scope is required" >&2
        usage >&2
        return 2
    fi

    _WISDOM_EDIT_RECORD_ID="$entry_id"
    _WISDOM_EDIT_SCOPE="$scope"
    _WISDOM_EDIT_PROJECT_ID="$project_id"
    _WISDOM_EDIT_DRY_RUN="$dry_run"
    
    # Validate at least one edit flag is provided
    if [[ -z "$set_body" && -z "$set_type" && -z "$set_tags" && -z "$add_tags" && -z "$set_score" && \
          -z "$set_authority" && -z "$set_status" && -z "$set_provenance" && -z "$set_origin_session" && \
          -z "$set_superseded_by" && -z "$set_contradicts" && -z "$set_verified_at" && -z "$set_review_due" ]]; then
        echo "Error: at least one edit flag must be provided" >&2
        usage >&2
        return 2
    fi
    
    # Validate type if provided
    if [[ -n "$set_type" ]]; then
        validate_type "$set_type" || return 2
    fi
    
    # Validate score if provided
    if [[ -n "$set_score" ]]; then
        validate_score "$set_score" || return 2
    fi

    if [[ -n "$set_authority" ]]; then
        validate_enum_from_array "$set_authority" "authority" "WISDOM_VALID_AUTHORITIES" || return 2
    fi

    if [[ -n "$set_status" ]]; then
        validate_enum_from_array "$set_status" "status" "WISDOM_VALID_STATUSES" || return 2
    fi

    if [[ -n "$set_provenance" ]]; then
        validate_enum_from_array "$set_provenance" "provenance" "WISDOM_VALID_PROVENANCES" || return 2
    fi
    
    # Check for secrets in new body if provided
    if [[ -n "$set_body" ]]; then
        if ! wisdom_check_secret "$set_body"; then
            return 3
        fi
    fi
    
    # Get store path
    local store_path
    store_path=$(wisdom_get_store_path "$scope" "$project_id") || return 2
    
    # Ensure store exists
    wisdom_init_store "$store_path"
    
    # Read current entry
    local current_json
    if ! current_json=$(wisdom_read_entry "$entry_id" "$store_path"); then
        echo "Error: entry '$entry_id' not found in scope '$scope'" >&2
        return 1
    fi

    _WISDOM_EDIT_AUTHORITY_BEFORE=$(printf '%s' "$current_json" | jq -r '.authority // "candidate"' 2>/dev/null || echo "")
    
    # Start building updated JSON
    local updated_json="$current_json"
    
    # Apply --set-body
    if [[ -n "$set_body" ]]; then
        changed_fields+=("body")
        local escaped_body
        escaped_body=$(wisdom_escape_json "$set_body")
        # escaped_body already has quotes, so use --argjson to pass as JSON string
        updated_json=$(echo "$updated_json" | jq --argjson body "$escaped_body" '.body = $body')
    fi
    
    # Apply --set-type
    if [[ -n "$set_type" ]]; then
        changed_fields+=("type")
        updated_json=$(echo "$updated_json" | jq --arg type "$set_type" '.type = $type')
    fi
    
    # Apply --set-tags
    if [[ -n "$set_tags" ]]; then
        changed_fields+=("tags")
        local tags_json
        tags_json=$(parse_tags_to_json "$set_tags")
        updated_json=$(echo "$updated_json" | jq --argjson tags "$tags_json" '.tags = $tags')
    fi
    
    # Apply --add-tags
    if [[ -n "$add_tags" ]]; then
        changed_fields+=("tags")
        local add_tags_json
        add_tags_json=$(parse_tags_to_json "$add_tags")
        updated_json=$(echo "$updated_json" | jq --argjson new_tags "$add_tags_json" '.tags = (.tags + $new_tags | unique)')
    fi
    
    # Apply --set-score
    if [[ -n "$set_score" ]]; then
        changed_fields+=("quality_score")
        updated_json=$(echo "$updated_json" | jq --argjson score "$set_score" '.quality_score = $score')
    fi
    
    # Apply --set-authority
    if [[ -n "$set_authority" ]]; then
        changed_fields+=("authority")
        updated_json=$(echo "$updated_json" | jq --arg authority "$set_authority" '.authority = $authority')
    fi

    # Apply --set-status
    if [[ -n "$set_status" ]]; then
        changed_fields+=("status")
        updated_json=$(echo "$updated_json" | jq --arg status "$set_status" '.status = $status')
    fi

    # Apply --set-provenance
    if [[ -n "$set_provenance" ]]; then
        changed_fields+=("provenance")
        updated_json=$(echo "$updated_json" | jq --arg provenance "$set_provenance" '.provenance = $provenance')
    fi

    # Apply --set-origin-session
    if [[ -n "$set_origin_session" ]]; then
        changed_fields+=("origin_session")
        updated_json=$(echo "$updated_json" | jq --arg origin_session "$set_origin_session" '.origin_session = $origin_session')
    fi
    
    # Apply --set-superseded-by
    if [[ -n "$set_superseded_by" ]]; then
        changed_fields+=("superseded_by")
        updated_json=$(echo "$updated_json" | jq --arg superseded_by "$set_superseded_by" '.superseded_by = $superseded_by')
    fi

    # Apply --set-contradicts
    if [[ -n "$set_contradicts" ]]; then
        changed_fields+=("contradicts")
        updated_json=$(echo "$updated_json" | jq --arg contradicts_id "$set_contradicts" '.contradicts = ((.contradicts // []) + [$contradicts_id] | unique)')
    fi
    
    # Apply --set-verified-at
    if [[ -n "$set_verified_at" ]]; then
        changed_fields+=("verified_at")
        updated_json=$(echo "$updated_json" | jq --arg verified_at "$set_verified_at" '.verified_at = $verified_at')
    fi
    
    # Apply --set-review-due
    if [[ -n "$set_review_due" ]]; then
        changed_fields+=("review_due")
        updated_json=$(echo "$updated_json" | jq --arg review_due "$set_review_due" '.review_due = $review_due')
    fi

    updated_json=$(printf '%s' "$updated_json" | jq -c '.')
    updated_json=$(wisdom_normalize_record "$updated_json") || return 2

    _WISDOM_EDIT_AUTHORITY_AFTER=$(printf '%s' "$updated_json" | jq -r '.authority // "candidate"' 2>/dev/null || echo "")
    _WISDOM_EDIT_CHANGED_FIELDS=$(jq -nc \
      --argjson before "$current_json" \
      --argjson after "$updated_json" \
      '["body","type","tags","quality_score","authority","status","provenance","origin_session","superseded_by","contradicts","verified_at","review_due"]
       | map(select((($before[.] // null)) != (($after[.] // null))))' 2>/dev/null || echo '[]')

    if ! wisdom_validate_jsonl_line "$updated_json"; then
        return 2
    fi
    
    # For dry-run, show before/after and exit
    if [[ "$dry_run" == true ]]; then
        echo "=== BEFORE ===" >&2
        echo "$current_json" | jq . >&2
        echo "" >&2
        echo "=== AFTER ===" >&2
        echo "$updated_json" | jq . >&2
        echo "" >&2
        echo "Dry run complete. No changes written." >&2
        return 0
    fi
    
    if wisdom_update_entry "$entry_id" "$store_path" "$updated_json"; then
        wisdom_log "INFO" "Entry '$entry_id' updated successfully"
        return 0
    else
        return 1
    fi
}

# Run main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
