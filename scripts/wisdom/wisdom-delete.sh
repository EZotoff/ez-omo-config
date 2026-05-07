#!/usr/bin/env bash
set -euo pipefail

# wisdom-delete.sh — Delete a wisdom entry by ID
# Usage: wisdom-delete.sh [OPTIONS] ID

# Source common functions
source "$(dirname "$0")/wisdom-common.sh"
wisdom_init_observability "$(basename "$0")"

_WISDOM_DELETE_START_MS=$(date +%s%3N 2>/dev/null || echo "")
_WISDOM_DELETE_ID=""
_WISDOM_DELETE_SCOPE=""
_WISDOM_DELETE_PROJECT_ID=""
_WISDOM_DELETE_DRY_RUN="false"
_WISDOM_DELETE_FORCE="false"
_WISDOM_DELETE_STORE_PATH=""
_WISDOM_DELETE_STATUS_BEFORE=""
_WISDOM_DELETE_AUTHORITY_BEFORE=""

_wisdom_delete_emit_observability() {
    local rc=$?
    local status="ok"
    [[ "$rc" -ne 0 ]] && status="error"

    local duration_ms_json="null"
    if [[ -n "${_WISDOM_DELETE_START_MS:-}" ]]; then
        local now_ms
        now_ms=$(date +%s%3N 2>/dev/null || echo "")
        if [[ -n "$now_ms" ]]; then
            duration_ms_json=$((now_ms - _WISDOM_DELETE_START_MS))
        fi
    fi

    local payload='{}'
    payload=$(jq -nc \
        --arg record_id "${_WISDOM_DELETE_ID:-}" \
        --arg scope "${_WISDOM_DELETE_SCOPE:-}" \
        --arg project_id "${_WISDOM_DELETE_PROJECT_ID:-}" \
        --arg dry_run "${_WISDOM_DELETE_DRY_RUN:-false}" \
        --arg force "${_WISDOM_DELETE_FORCE:-false}" \
        --arg store_path "${_WISDOM_DELETE_STORE_PATH:-}" \
        --arg status_before "${_WISDOM_DELETE_STATUS_BEFORE:-}" \
        --arg status_after "deleted" \
        --arg authority_before "${_WISDOM_DELETE_AUTHORITY_BEFORE:-}" \
        --argjson duration_ms "$duration_ms_json" \
        '{
            affected_count: (if $record_id == "" then 0 else 1 end),
            affected_ids: (if $record_id == "" then [] else [$record_id] end),
            scope: (if $scope == "" then null else $scope end),
            project_id: (if $project_id == "" then null else $project_id end),
            dry_run: ($dry_run == "true"),
            force: ($force == "true"),
            store_path: (if $store_path == "" then null else $store_path end),
            status_before: (if $status_before == "" then null else $status_before end),
            status_after: $status_after,
            authority_before: (if $authority_before == "" then null else $authority_before end),
            authority_after: null,
            duration_ms: $duration_ms
        }' 2>/dev/null) || payload='{}'

    wisdom_emit_event "wisdom.lifecycle.delete" "$status" "$payload"
}

trap _wisdom_delete_emit_observability EXIT

# --------------------------------------------------------------------------
# Help/usage
# --------------------------------------------------------------------------
usage() {
    cat <<EOF
wisdom-delete.sh — Delete a wisdom entry by ID

Usage: wisdom-delete.sh [--id] ID [OPTIONS]

Arguments:
  ID                        Entry ID to delete (required)
  --id                      Flag prefix for entry ID (optional)

Options:
  --scope SCOPE             Scope of the entry (required)
                            Valid: system, project, plan
  --project-id ID           Project/plan identifier (required for project/plan scope)
  --dry-run                 Show what would be deleted, but don't delete
  --force                   Skip confirmation prompt
  -h, --help                Show this help message

Exit codes:
  0  Entry deleted successfully
  1  Entry not found
  2  Bad arguments or validation error
  3  User cancelled deletion

Examples:
  # Delete a system entry with confirmation
  wisdom-delete.sh --scope system 20250304-123456-abcd

  # Delete a project entry without confirmation
  wisdom-delete.sh --scope project --project-id myproject --force 20250304-123456-abcd

  # Show what would be deleted (dry run)
  wisdom-delete.sh --scope system --dry-run 20250304-123456-abcd
EOF
}

# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------
main() {
    # Parse arguments
    local id=""
    local scope=""
    local project_id=""
    local dry_run=false
    local force=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage
                exit 0
                ;;
            --id)
                id="$2"
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
            --dry-run)
                dry_run=true
                shift
                ;;
            --force)
                force=true
                shift
                ;;
            --*)
                wisdom_log "ERROR" "Unknown option: $1"
                usage >&2
                exit 2
                ;;
            -*)
                wisdom_log "ERROR" "Unknown option: $1"
                usage >&2
                exit 2
                ;;
            *)
                # Positional argument: ID
                if [[ -z "$id" ]]; then
                    id="$1"
                    shift
                else
                    wisdom_log "ERROR" "Unexpected argument: $1"
                    usage >&2
                    exit 2
                fi
                ;;
        esac
    done

    # Validate required arguments
    if [[ -z "$id" ]]; then
        wisdom_log "ERROR" "Missing required argument: ID"
        usage >&2
        exit 2
    fi

    if [[ -z "$scope" ]]; then
        wisdom_log "ERROR" "Missing required option: --scope"
        usage >&2
        exit 2
    fi

    _WISDOM_DELETE_ID="$id"
    _WISDOM_DELETE_SCOPE="$scope"
    _WISDOM_DELETE_PROJECT_ID="$project_id"
    _WISDOM_DELETE_DRY_RUN="$dry_run"
    _WISDOM_DELETE_FORCE="$force"

    # Validate project_id requirement for project/plan scope
    if [[ "$scope" == "project" || "$scope" == "plan" ]] && [[ -z "$project_id" ]]; then
        wisdom_log "ERROR" "Scope '$scope' requires --project-id"
        usage >&2
        exit 2
    fi

    # Ensure jq is available
    wisdom_require_jq || exit 2

    # Get store path
    local store_path
    store_path=$(wisdom_get_store_path "$scope" "$project_id") || exit 2
    _WISDOM_DELETE_STORE_PATH="$store_path"

    # Check if store exists
    if [[ ! -f "$store_path" ]]; then
        wisdom_log "ERROR" "Store file not found: $store_path"
        exit 1
    fi

    # Read the entry
    local entry_json
    if ! entry_json=$(wisdom_read_entry "$id" "$store_path"); then
        wisdom_log "ERROR" "Entry '$id' not found in $store_path"
        exit 1
    fi

    _WISDOM_DELETE_STATUS_BEFORE=$(printf '%s' "$entry_json" | jq -r '.status // "active"' 2>/dev/null || echo "")
    _WISDOM_DELETE_AUTHORITY_BEFORE=$(printf '%s' "$entry_json" | jq -r '.authority // "candidate"' 2>/dev/null || echo "")

    # Extract entry details for display
    local entry_type entry_body entry_created
    entry_type=$(printf '%s' "$entry_json" | jq -r '.type')
    entry_body=$(printf '%s' "$entry_json" | jq -r '.body')
    entry_created=$(printf '%s' "$entry_json" | jq -r '.created')

    # Truncate body for display
    local display_body
    if [[ ${#entry_body} -gt 100 ]]; then
        display_body="${entry_body:0:100}..."
    else
        display_body="$entry_body"
    fi

    # Display entry details
    cat <<EOF

Entry to delete:
  ID:      $id
  Type:    $entry_type
  Scope:   $scope
  Created: $entry_created
  Body:    $display_body

EOF

    # Handle dry-run mode
    if [[ "$dry_run" == true ]]; then
        wisdom_log "INFO" "[DRY-RUN] Would delete entry: $id"
        exit 0
    fi

    # Handle force mode or ask for confirmation
    if [[ "$force" == true ]]; then
        wisdom_log "INFO" "Deleting entry '$id' (--force flag used)"
    else
        # Check for non-interactive context
        if ! ( exec 3</dev/tty ) 2>/dev/null; then
            wisdom_log "ERROR" "Non-interactive context. Use --force to skip confirmation."
            exit 1
        fi
        # Ask for confirmation
        printf "Delete this entry? [y/N] " >&2
        read -r answer < /dev/tty

        if [[ ! "$answer" =~ ^[Yy]$ ]]; then
            wisdom_log "INFO" "Deletion cancelled by user"
            exit 3
        fi
    fi

    if wisdom_remove_entry "$id" "$store_path"; then
        wisdom_log "INFO" "Entry '$id' deleted successfully"
        exit 0
    else
        wisdom_log "ERROR" "Failed to delete entry '$id'"
        exit 1
    fi
}

# Run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
