#!/usr/bin/env bash
set -euo pipefail

# wisdom-archive.sh — Move a wisdom entry from active store to archive store
# Usage: wisdom-archive.sh [OPTIONS] ID

# Source common functions
source "$(dirname "$0")/wisdom-common.sh"
wisdom_init_observability "$(basename "$0")"

_WISDOM_ARCHIVE_START_MS=$(date +%s%3N 2>/dev/null || echo "")
_WISDOM_ARCHIVE_ID=""
_WISDOM_ARCHIVE_SCOPE=""
_WISDOM_ARCHIVE_PROJECT_ID=""
_WISDOM_ARCHIVE_DRY_RUN="false"
_WISDOM_ARCHIVE_ACTIVE_STORE=""
_WISDOM_ARCHIVE_ARCHIVE_STORE=""
_WISDOM_ARCHIVE_STATUS_BEFORE=""
_WISDOM_ARCHIVE_STATUS_AFTER=""
_WISDOM_ARCHIVE_AUTHORITY_BEFORE=""
_WISDOM_ARCHIVE_AUTHORITY_AFTER=""

_wisdom_archive_emit_observability() {
    local rc=$?
    local status="success"
    [[ "$rc" -ne 0 ]] && status="failed"

    local duration_ms_json="null"
    if [[ -n "${_WISDOM_ARCHIVE_START_MS:-}" ]]; then
        local now_ms
        now_ms=$(date +%s%3N 2>/dev/null || echo "")
        if [[ -n "$now_ms" ]]; then
            duration_ms_json=$((now_ms - _WISDOM_ARCHIVE_START_MS))
        fi
    fi

    local payload='{}'
    payload=$(jq -nc \
        --arg record_id "${_WISDOM_ARCHIVE_ID:-}" \
        --arg scope "${_WISDOM_ARCHIVE_SCOPE:-}" \
        --arg project_id "${_WISDOM_ARCHIVE_PROJECT_ID:-}" \
        --arg dry_run "${_WISDOM_ARCHIVE_DRY_RUN:-false}" \
        --arg active_store_path "${_WISDOM_ARCHIVE_ACTIVE_STORE:-}" \
        --arg archive_store_path "${_WISDOM_ARCHIVE_ARCHIVE_STORE:-}" \
        --arg status_before "${_WISDOM_ARCHIVE_STATUS_BEFORE:-}" \
        --arg status_after "${_WISDOM_ARCHIVE_STATUS_AFTER:-}" \
        --arg authority_before "${_WISDOM_ARCHIVE_AUTHORITY_BEFORE:-}" \
        --arg authority_after "${_WISDOM_ARCHIVE_AUTHORITY_AFTER:-}" \
        --argjson duration_ms "$duration_ms_json" \
        '{
            affected_count: (if $record_id == "" then 0 else 1 end),
            affected_ids: (if $record_id == "" then [] else [$record_id] end),
            scope: (if $scope == "" then null else $scope end),
            project_id: (if $project_id == "" then null else $project_id end),
            dry_run: ($dry_run == "true"),
            active_store_path: (if $active_store_path == "" then null else $active_store_path end),
            archive_store_path: (if $archive_store_path == "" then null else $archive_store_path end),
            status_before: (if $status_before == "" then null else $status_before end),
            status_after: (if $status_after == "" then null else $status_after end),
            authority_before: (if $authority_before == "" then null else $authority_before end),
            authority_after: (if $authority_after == "" then null else $authority_after end),
            duration_ms: $duration_ms
        }' 2>/dev/null) || payload='{}'

    wisdom_emit_event "wisdom.lifecycle.archive" "$status" "$payload"
}

trap _wisdom_archive_emit_observability EXIT

# --------------------------------------------------------------------------
# Help/usage
# --------------------------------------------------------------------------
usage() {
    cat <<EOF
wisdom-archive.sh — Archive a wisdom entry by ID

Usage: wisdom-archive.sh [--id] ID [OPTIONS]

Arguments:
  ID                        Entry ID to archive (required)
  --id                      Flag prefix for entry ID (optional)

Options:
  --scope SCOPE             Scope of the entry (required)
                            Valid: system, project, plan
  --project-id ID           Project/plan identifier (required for project/plan scope)
  --dry-run                 Show what would be archived, but don't archive
  -h, --help                Show this help message

Exit codes:
  0  Entry archived successfully
  1  Entry not found
  2  Bad arguments or validation error

Examples:
  # Archive a system entry
  wisdom-archive.sh --scope system 20250304-123456-abcd

  # Archive a project entry
  wisdom-archive.sh --scope project --project-id myproject 20250304-123456-abcd

  # Show what would be archived (dry run)
  wisdom-archive.sh --scope system --dry-run 20250304-123456-abcd
EOF
}

# --------------------------------------------------------------------------
# Get archive store path for a given scope
# Args: $1=scope, $2=project_id (for project/plan scope)
# Returns: path on stdout
# --------------------------------------------------------------------------
get_archive_store_path() {
    local scope="${1:-}"
    local project_id="${2:-}"

    case "$scope" in
        system)  printf '%s\n' "${WISDOM_ROOT}/archive/system.jsonl" ;;
        project) printf '%s\n' "${WISDOM_ROOT}/archive/projects/${project_id}.jsonl" ;;
        plan)    printf '%s\n' "${WISDOM_ROOT}/archive/plans/${project_id}.jsonl" ;;
        *)       return 1 ;;
    esac
    return 0
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

    _WISDOM_ARCHIVE_ID="$id"
    _WISDOM_ARCHIVE_SCOPE="$scope"
    _WISDOM_ARCHIVE_PROJECT_ID="$project_id"
    _WISDOM_ARCHIVE_DRY_RUN="$dry_run"

    # Validate project_id requirement for project/plan scope
    if [[ "$scope" == "project" || "$scope" == "plan" ]] && [[ -z "$project_id" ]]; then
        wisdom_log "ERROR" "Scope '$scope' requires --project-id"
        usage >&2
        exit 2
    fi

    # Ensure jq is available
    wisdom_require_jq || exit 2

    # Get active store path
    local active_store_path
    active_store_path=$(wisdom_get_store_path "$scope" "$project_id") || exit 2
    _WISDOM_ARCHIVE_ACTIVE_STORE="$active_store_path"

    # Check if active store exists
    if [[ ! -f "$active_store_path" ]]; then
        wisdom_log "ERROR" "Active store file not found: $active_store_path"
        exit 1
    fi

    # Read the entry from active store
    local entry_json
    if ! entry_json=$(wisdom_read_entry "$id" "$active_store_path"); then
        wisdom_log "ERROR" "Entry '$id' not found in active store"
        exit 1
    fi

    _WISDOM_ARCHIVE_STATUS_BEFORE=$(printf '%s' "$entry_json" | jq -r '.status // "active"' 2>/dev/null || echo "")
    _WISDOM_ARCHIVE_AUTHORITY_BEFORE=$(printf '%s' "$entry_json" | jq -r '.authority // "candidate"' 2>/dev/null || echo "")

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

Entry to archive:
  ID:      $id
  Type:    $entry_type
  Scope:   $scope
  Created: $entry_created
  Body:    $display_body

EOF

    # Handle dry-run mode
    if [[ "$dry_run" == true ]]; then
        _WISDOM_ARCHIVE_STATUS_AFTER="${_WISDOM_ARCHIVE_STATUS_BEFORE:-archived}"
        _WISDOM_ARCHIVE_AUTHORITY_AFTER="${_WISDOM_ARCHIVE_AUTHORITY_BEFORE:-}"
        wisdom_log "INFO" "[DRY-RUN] Would archive entry: $id"
        exit 0
    fi

    # Get archive store path
    local archive_store_path
    archive_store_path=$(get_archive_store_path "$scope" "$project_id") || {
        wisdom_log "ERROR" "Failed to determine archive store path"
        exit 2
    }
    _WISDOM_ARCHIVE_ARCHIVE_STORE="$archive_store_path"

    # Initialize archive store if needed
    wisdom_init_store "$archive_store_path" || {
        wisdom_log "ERROR" "Failed to initialize archive store"
        exit 2
    }

    # Append to archive store FIRST (write-first-then-delete order)
    if ! wisdom_append_entry "$entry_json" "$archive_store_path"; then
        wisdom_log "ERROR" "Failed to write entry to archive store"
        exit 2
    fi

    # Remove from active store SECOND
    if ! wisdom_remove_entry "$id" "$active_store_path"; then
        wisdom_log "ERROR" "Failed to remove entry from active store"
        exit 2
    fi

    _WISDOM_ARCHIVE_STATUS_AFTER="archived"
    _WISDOM_ARCHIVE_AUTHORITY_AFTER="${_WISDOM_ARCHIVE_AUTHORITY_BEFORE:-}"

    wisdom_log "INFO" "Entry '$id' archived successfully"
    exit 0
}

# Run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
