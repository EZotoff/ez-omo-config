#!/usr/bin/env bash
set -euo pipefail

# wisdom-gc.sh — Garbage collection for stale/low-quality wisdom entries
# Identifies entries matching staleness criteria and can report, archive, or delete them.
# Usage: wisdom-gc.sh [OPTIONS]

# Source shared library
source "$(dirname "$0")/wisdom-common.sh"
wisdom_require_jq

# --------------------------------------------------------------------------
# Help/usage
# --------------------------------------------------------------------------
usage() {
    cat >&2 <<'EOF'
Usage: wisdom-gc.sh [OPTIONS]

Garbage collection for wisdom entries. Identifies stale or low-quality entries
and can report, archive, or delete them.

Options:
  --scope SCOPE          all|system|project|plan (default: all)
  --project-id ID        Required when --scope is project or plan
  --stale-days N         Days to consider an entry stale (default: 90)
  --min-score N          Minimum quality_score; below this is flagged (default: 0)
  --action ACTION        report|archive|delete (default: report)
  --dry-run              Show what would be done, don't modify
  --force                Skip confirmation for delete action
  --help, -h             Show this help

Staleness criteria (ANY match = flagged):
  1. accessed == 0 AND created > stale-days ago
  2. last_accessed is non-empty AND > stale-days old
  3. quality_score > 0 AND quality_score < min-score

Actions:
  report   Print flagged entries with reason (no changes)
  archive  Move flagged entries to archive via wisdom-archive.sh
  delete   Remove flagged entries (requires --force)

Exit codes:
  0  Success (entries found/processed)
  1  No stale entries found
  2  Bad arguments

Examples:
  # Report all stale entries in system scope
  wisdom-gc.sh --scope system

  # Delete all entries with quality_score < 50 (requires --force)
  wisdom-gc.sh --min-score 50 --action delete --force

  # Dry-run: show what would be archived
  wisdom-gc.sh --action archive --dry-run
EOF
    exit 2
}

# --------------------------------------------------------------------------
# Helper: Derive scope and project_id from store file path
# --------------------------------------------------------------------------
_derive_scope_and_id() {
    local store_path="$1"
    local file_name
    file_name=$(basename "$store_path" .jsonl)

    if [[ "$store_path" == "${WISDOM_ROOT}/system.jsonl" ]]; then
        echo "system|"
    elif [[ "$store_path" == "${WISDOM_ROOT}/projects/"* ]]; then
        echo "project|${file_name}"
    elif [[ "$store_path" == "${WISDOM_ROOT}/plans/"* ]]; then
        echo "plan|${file_name}"
    fi
}

# --------------------------------------------------------------------------
# Helper: Check if an entry is stale (accepts pre-extracted fields)
# Args: $1=created, $2=accessed, $3=last_accessed, $4=quality_score, $5=stale_cutoff, $6=min_score
# Returns 0 (stale) or 1 (not stale), outputs reason on stdout
# --------------------------------------------------------------------------
_is_stale() {
    local created="$1"
    local accessed="$2"
    local last_accessed="$3"
    local quality_score="$4"
    local stale_cutoff="$5"
    local min_score="$6"

    if [[ "$accessed" == "0" || "$accessed" == "" ]] && [[ -n "$created" ]]; then
        local created_epoch
        created_epoch=$(date -d "$created" +%s 2>/dev/null || echo 0)
        if [[ "$created_epoch" -lt "$stale_cutoff" ]]; then
            local days_old=$(( ($stale_cutoff - $created_epoch) / 86400 ))
            echo "Never accessed, created $days_old days ago"
            return 0
        fi
    fi

    if [[ -n "$last_accessed" && "$last_accessed" != "null" && "$last_accessed" != "" ]]; then
        local last_accessed_epoch
        last_accessed_epoch=$(date -d "$last_accessed" +%s 2>/dev/null || echo 0)
        if [[ "$last_accessed_epoch" -lt "$stale_cutoff" ]]; then
            local days_old=$(( ($stale_cutoff - $last_accessed_epoch) / 86400 ))
            echo "Last accessed $days_old days ago"
            return 0
        fi
    fi

    if [[ "$quality_score" != "null" ]] && \
       { [[ "$quality_score" =~ ^[0-9]+$ ]]; }; then
        if [[ "$quality_score" -gt 0 && "$quality_score" -lt "$min_score" ]]; then
            echo "Low quality score: $quality_score (threshold: $min_score)"
            return 0
        fi
    fi

    return 1
}

# --------------------------------------------------------------------------
# Helper: Format entry for display
# Truncate body to ~60 chars
# --------------------------------------------------------------------------
_format_entry() {
    local id="$1"
    local scope="$2"
    local type="$3"
    local reason="$4"
    local body="$5"

    local truncated_body="${body:0:60}"
    if [[ ${#body} -gt 60 ]]; then
        truncated_body="${truncated_body}..."
    fi

    printf '[STALE] id=%-25s scope=%-8s type=%-8s\n' "$id" "$scope" "$type"
    printf '        Reason: %s\n' "$reason"
    printf '        Body: "%s"\n' "$truncated_body"
}

# --------------------------------------------------------------------------
# Main entry point
# --------------------------------------------------------------------------
main() {
    local scope="all"
    local project_id=""
    local stale_days=90
    local min_score=0
    local action="report"
    local dry_run=false
    local force=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --scope)
                [[ $# -lt 2 ]] && { wisdom_log ERROR "--scope requires a value"; usage; }
                scope="$2"; shift 2 ;;
            --project-id)
                [[ $# -lt 2 ]] && { wisdom_log ERROR "--project-id requires a value"; usage; }
                project_id="$2"; shift 2 ;;
            --stale-days)
                [[ $# -lt 2 ]] && { wisdom_log ERROR "--stale-days requires a value"; usage; }
                stale_days="$2"; shift 2 ;;
            --min-score)
                [[ $# -lt 2 ]] && { wisdom_log ERROR "--min-score requires a value"; usage; }
                min_score="$2"; shift 2 ;;
            --action)
                [[ $# -lt 2 ]] && { wisdom_log ERROR "--action requires a value"; usage; }
                action="$2"; shift 2 ;;
            --dry-run)
                dry_run=true; shift ;;
            --force)
                force=true; shift ;;
            --help|-h)
                usage ;;
            *)
                wisdom_log ERROR "Unknown option: $1"
                usage ;;
        esac
    done

    # Validate scope
    case "$scope" in
        all|system|project|plan) ;;
        *)
            wisdom_log ERROR "Invalid scope: $scope"
            exit 2
            ;;
    esac

    if [[ "$scope" == "project" || "$scope" == "plan" ]] && [[ -z "$project_id" ]]; then
        wisdom_log ERROR "scope '$scope' requires --project-id"
        exit 2
    fi

    if ! [[ "$stale_days" =~ ^[0-9]+$ ]]; then
        wisdom_log ERROR "--stale-days must be a non-negative integer"
        exit 2
    fi

    if ! [[ "$min_score" =~ ^[0-9]+$ ]]; then
        wisdom_log ERROR "--min-score must be a non-negative integer"
        exit 2
    fi

    case "$action" in
        report|archive|delete) ;;
        *)
            wisdom_log ERROR "Invalid action: $action (valid: report|archive|delete)"
            exit 2
            ;;
    esac

    # Compute cutoff timestamp for staleness
    local stale_cutoff
    stale_cutoff=$(date -d "-${stale_days} days" +%s)

    # Collect JSONL store files based on scope
    declare -a store_files=()

    _add_file_if_exists() {
        local f="$1"
        if [[ -f "$f" && -s "$f" ]]; then
            store_files+=("$f")
        fi
    }

    case "$scope" in
        all)
            _add_file_if_exists "${WISDOM_ROOT}/system.jsonl"
            if [[ -d "${WISDOM_ROOT}/projects" ]]; then
                for f in "${WISDOM_ROOT}/projects"/*.jsonl; do
                    _add_file_if_exists "$f"
                done
            fi
            if [[ -d "${WISDOM_ROOT}/plans" ]]; then
                for f in "${WISDOM_ROOT}/plans"/*.jsonl; do
                    _add_file_if_exists "$f"
                done
            fi
            ;;
        system)
            _add_file_if_exists "${WISDOM_ROOT}/system.jsonl"
            ;;
        project)
            _add_file_if_exists "${WISDOM_ROOT}/projects/${project_id}.jsonl"
            ;;
        plan)
            _add_file_if_exists "${WISDOM_ROOT}/plans/${project_id}.jsonl"
            ;;
    esac

    # Process all store files
    declare -a stale_entries=()
    local stale_never_accessed=0
    local stale_last_accessed=0
    local stale_low_score=0

    for store_path in "${store_files[@]}"; do
         IFS='|' read -r entry_scope entry_pid < <(_derive_scope_and_id "$store_path")

         while IFS= read -r line; do
             [[ -z "$line" ]] && continue

             local id type created accessed last_accessed quality_score body reason
             read -r id type created accessed last_accessed quality_score < <(
                 printf '%s' "$line" | jq -r '[.id, .type, .created, (.accessed // 0), (.last_accessed // ""), (.quality_score // 0)] | @tsv' 2>/dev/null
             ) || { id=""; type=""; }
             body=$(printf '%s' "$line" | jq -r '.body // ""' 2>/dev/null) || body=""

             reason=$(_is_stale "$created" "$accessed" "$last_accessed" "$quality_score" "$stale_cutoff" "$min_score") && {
                 local body_encoded
                 body_encoded=$(printf '%s' "$body" | base64 | tr -d '\n')
                 stale_entries+=("${id}|${entry_scope}|${entry_pid}|${type}|${reason}|${body_encoded}")

                 case "$reason" in
                     *"Never accessed"*) ((++stale_never_accessed)) ;;
                     *"Last accessed"*) ((++stale_last_accessed)) ;;
                     *"Low quality"*) ((++stale_low_score)) ;;
                 esac
             } || true
         done < <(jq -c '.' "$store_path" 2>/dev/null)
     done

    # If no stale entries found, exit 1
    if [[ ${#stale_entries[@]} -eq 0 ]]; then
        wisdom_log INFO "No stale entries found."
        exit 1
    fi

    # Execute action: report (default)
    if [[ "$action" == "report" ]]; then
        echo ""
        echo "=== Wisdom GC Report ==="
        echo "Scope: $scope | Stale days: $stale_days | Min score: $min_score"
        echo ""

        for entry_data in "${stale_entries[@]}"; do
            IFS='|' read -r id entry_scope entry_pid type reason body_encoded <<< "$entry_data"
            body=$(printf '%s' "$body_encoded" | base64 -d 2>/dev/null || echo "[decode error]")
            _format_entry "$id" "$entry_scope" "$type" "$reason" "$body"
            echo ""
        done

        local total=$((stale_never_accessed + stale_last_accessed + stale_low_score))
        echo "Summary: $total stale entries found ($stale_never_accessed never-accessed, $stale_last_accessed last-accessed, $stale_low_score low-score)"
        exit 0
    fi

    # Execute action: archive
    if [[ "$action" == "archive" ]]; then
        local archived=0
        local failed=0

        echo "=== Archiving Stale Entries ==="
        [[ "$dry_run" == true ]] && echo "[DRY-RUN]"
        echo ""

        for entry_data in "${stale_entries[@]}"; do
            IFS='|' read -r id entry_scope entry_pid type reason body_encoded <<< "$entry_data"
            body=$(printf '%s' "$body_encoded" | base64 -d 2>/dev/null || echo "[decode error]")
            _format_entry "$id" "$entry_scope" "$type" "$reason" "$body"

            if [[ "$dry_run" == false ]]; then
                # Call wisdom-archive.sh
                if [[ "$entry_scope" == "system" ]]; then
                    if "$(dirname "$0")/wisdom-archive.sh" --id "$id" --scope "$entry_scope" >/dev/null 2>&1; then
                        echo "        ✓ Archived"
                        ((++archived))
                    else
                        echo "        ✗ Archive failed"
                        ((++failed))
                    fi
                else
                    if "$(dirname "$0")/wisdom-archive.sh" --id "$id" --scope "$entry_scope" --project-id "$entry_pid" >/dev/null 2>&1; then
                        echo "        ✓ Archived"
                        ((++archived))
                    else
                        echo "        ✗ Archive failed"
                        ((++failed))
                    fi
                fi
            else
                echo "        [DRY-RUN] Would archive"
            fi
            echo ""
        done

        if [[ "$dry_run" == false ]]; then
            echo "Summary: $archived archived, $failed failed"
        else
            echo "Summary: ${#stale_entries[@]} entries would be archived"
        fi
        exit 0
    fi

    # Execute action: delete
    if [[ "$action" == "delete" ]]; then
        if [[ "$force" == false ]]; then
            wisdom_log WARN "delete action requires --force flag"
            echo ""
            echo "=== Preview: Would Delete These Entries ==="
            echo ""

            for entry_data in "${stale_entries[@]}"; do
                IFS='|' read -r id entry_scope entry_pid type reason body_encoded <<< "$entry_data"
                body=$(printf '%s' "$body_encoded" | base64 -d 2>/dev/null || echo "[decode error]")
                _format_entry "$id" "$entry_scope" "$type" "$reason" "$body"
                echo ""
            done

            local total=$((stale_never_accessed + stale_last_accessed + stale_low_score))
            echo "Summary: Would delete $total entries (use --force to confirm)"
            exit 1
        fi

        local deleted=0
        local failed=0

        echo "=== Deleting Stale Entries ==="
        [[ "$dry_run" == true ]] && echo "[DRY-RUN]"
        echo ""

        for entry_data in "${stale_entries[@]}"; do
            IFS='|' read -r id entry_scope entry_pid type reason body_encoded <<< "$entry_data"
            body=$(printf '%s' "$body_encoded" | base64 -d 2>/dev/null || echo "[decode error]")
            _format_entry "$id" "$entry_scope" "$type" "$reason" "$body"

            if [[ "$dry_run" == false ]]; then
                local store_path
                if [[ "$entry_scope" == "system" ]]; then
                    store_path="${WISDOM_ROOT}/system.jsonl"
                elif [[ "$entry_scope" == "project" ]]; then
                    store_path="${WISDOM_ROOT}/projects/${entry_pid}.jsonl"
                elif [[ "$entry_scope" == "plan" ]]; then
                    store_path="${WISDOM_ROOT}/plans/${entry_pid}.jsonl"
                fi

                if wisdom_remove_entry "$id" "$store_path" >/dev/null 2>&1; then
                    echo "        ✓ Deleted"
                    ((++deleted))
                else
                    echo "        ✗ Delete failed"
                    ((++failed))
                fi
            else
                echo "        [DRY-RUN] Would delete"
            fi
            echo ""
        done

        if [[ "$dry_run" == false ]]; then
            echo "Summary: $deleted deleted, $failed failed"
        else
            echo "Summary: ${#stale_entries[@]} entries would be deleted"
        fi
        exit 0
    fi

    exit 0
}

# Guard for sourcing
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
