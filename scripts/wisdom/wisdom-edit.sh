#!/usr/bin/env bash
set -euo pipefail

# wisdom-edit.sh — Edit individual fields of a wisdom entry by ID
# Usage: wisdom-edit.sh ID --scope SCOPE [--project-id PROJECT] [edit-flags] [--dry-run]

# Source common functions
source "$(dirname "$0")/wisdom-common.sh"

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
    
    # Validate at least one edit flag is provided
    if [[ -z "$set_body" && -z "$set_type" && -z "$set_tags" && -z "$add_tags" && -z "$set_score" ]]; then
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
    
    # Start building updated JSON
    local updated_json="$current_json"
    
    # Apply --set-body
    if [[ -n "$set_body" ]]; then
        local escaped_body
        escaped_body=$(wisdom_escape_json "$set_body")
        # escaped_body already has quotes, so use --argjson to pass as JSON string
        updated_json=$(echo "$updated_json" | jq --argjson body "$escaped_body" '.body = $body')
    fi
    
    # Apply --set-type
    if [[ -n "$set_type" ]]; then
        updated_json=$(echo "$updated_json" | jq --arg type "$set_type" '.type = $type')
    fi
    
    # Apply --set-tags
    if [[ -n "$set_tags" ]]; then
        local tags_json
        tags_json=$(parse_tags_to_json "$set_tags")
        updated_json=$(echo "$updated_json" | jq --argjson tags "$tags_json" '.tags = $tags')
    fi
    
    # Apply --add-tags
    if [[ -n "$add_tags" ]]; then
        local add_tags_json
        add_tags_json=$(parse_tags_to_json "$add_tags")
        updated_json=$(echo "$updated_json" | jq --argjson new_tags "$add_tags_json" '.tags = (.tags + $new_tags | unique)')
    fi
    
    # Apply --set-score
    if [[ -n "$set_score" ]]; then
        updated_json=$(echo "$updated_json" | jq --argjson score "$set_score" '.quality_score = $score')
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