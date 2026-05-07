#!/usr/bin/env bash
set -euo pipefail

# wisdom-search.sh — Search JSONL wisdom stores with filtering, sorting, and access tracking
# Usage: wisdom-search.sh QUERY [OPTIONS]

# Source shared library
source "$(dirname "$0")/wisdom-common.sh"
wisdom_init_observability "$(basename "$0")"
wisdom_require_jq

# --------------------------------------------------------------------------
# Defaults
# --------------------------------------------------------------------------
QUERY=""
SCOPE="all"
TYPE=""
TAGS=""
LIMIT=10
JSON_OUTPUT=false
MIN_SCORE=""
PROJECT_ID=""
AUTHORITY_FILTER=""
INCLUDE_STATUS=""
PROVENANCE_FILTER=""
ORIGIN_SESSION_FILTER=""
TOUCH=false

# --------------------------------------------------------------------------
# Usage
# --------------------------------------------------------------------------
usage() {
    cat >&2 <<'EOF'
Usage: wisdom-search.sh QUERY [OPTIONS]

Arguments:
  QUERY                  Search string (required, case-insensitive substring match on body)

Options:
  --scope SCOPE          system|project|plan|all (default: all)
  --type TYPE            gotcha|pattern|fact|decision|warning (filter)
  --tags TAGS            Comma-separated tags, any match (filter)
  --limit N              Max results to return (default: 10)
  --json                 Output as JSON array
  --min-score N          Filter by quality_score >= N
  --project-id ID        Limit to specific project (with --scope project or plan)
  --authority LEVEL      Filter by authority level: candidate|verified|published
  --include-status LIST  Also include statuses: superseded,retracted
  --provenance VALUE     Filter by provenance value
  --origin-session ID    Filter by origin_session
  --touch                Update access telemetry (accessed count, last_accessed)
  --help, -h             Show this help

Exit codes:
  0  Found results
  1  No results found
  2  Bad arguments
EOF
    exit 2
}

emit_wisdom_search_event() {
    local evt_status="$1"
    local evt_reason="${2:-}"
    local evt_returned="${3:-0}"

    local payload
    payload=$(jq -n \
        --arg query_hash "${query_hash:-}" \
        --arg query_preview "${query_preview:-}" \
        --arg scope "$SCOPE" \
        --arg project_id "${PROJECT_ID:-}" \
        --arg type "${TYPE:-}" \
        --arg authority "${AUTHORITY_FILTER:-}" \
        --arg provenance "${PROVENANCE_FILTER:-}" \
        --arg include_status "${INCLUDE_STATUS:-}" \
        --argjson touch "$([[ "$TOUCH" == true ]] && echo true || echo false)" \
        --argjson scanned "${scanned_count:-0}" \
        --argjson matched "${matched_count:-0}" \
        --argjson returned "$evt_returned" \
        '{
            query_hash: $query_hash,
            query_preview: $query_preview,
            scope: $scope,
            project_id: $project_id,
            type: $type,
            authority: $authority,
            provenance: $provenance,
            include_status: $include_status,
            touch: $touch,
            counts: {
                scanned: $scanned,
                matched: $matched,
                returned: $returned
            }
        }' 2>/dev/null) || payload="{}"

    if [[ -n "$evt_reason" ]]; then
        payload=$(printf '%s' "$payload" | jq --arg reason "$evt_reason" '. + {reason: $reason}' 2>/dev/null) || true
    fi

    wisdom_emit_event "wisdom.search" "$evt_status" "$payload" 2>/dev/null || true
}

trim_whitespace() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

parse_csv_list() {
    local csv="$1"
    local output_name="$2"
    local -n output_ref="$output_name"
    local raw_items=()
    local item trimmed

    output_ref=()
    IFS=',' read -r -a raw_items <<< "$csv"
    for item in "${raw_items[@]}"; do
        trimmed=$(trim_whitespace "$item")
        [[ -z "$trimmed" ]] && continue
        output_ref+=("$trimmed")
    done
}

array_contains() {
    local needle="$1"
    shift
    local item

    for item in "$@"; do
        if [[ "$item" == "$needle" ]]; then
            return 0
        fi
    done

    return 1
}

validate_enum_value() {
    local value="$1"
    local field_name="$2"
    local valid_values_name="$3"
    local -n valid_values_ref="$valid_values_name"

    if ! array_contains "$value" "${valid_values_ref[@]}"; then
        wisdom_log ERROR "Invalid ${field_name}: ${value} (valid: ${valid_values_ref[*]})"
        usage
    fi
}

entry_has_mutual_contradiction() {
    local first_entry="$1"
    local second_entry="$2"

    jq -nr --argjson first "$first_entry" --argjson second "$second_entry" '
        def normalize_text:
            if . == null then ""
            else ascii_downcase | gsub("[^a-z0-9]+"; " ") | gsub("^ +| +$"; "")
            end;
        def topic_key($entry): (($entry.title // $entry.body // "") | normalize_text);
        def body_key($entry): (($entry.body // "") | normalize_text);
        topic_key($first) != ""
        and topic_key($first) == topic_key($second)
        and $first.status == $second.status
        and $first.authority == $second.authority
        and body_key($first) != body_key($second)
        and (($first.contradicts // []) | index($second.id)) != null
        and (($second.contradicts // []) | index($first.id)) != null
    '
}

entries_share_conflict_rank() {
    local first_ranked_entry="$1"
    local second_ranked_entry="$2"

    jq -nr --argjson first "$first_ranked_entry" --argjson second "$second_ranked_entry" '
        $first._rank.relevance == $second._rank.relevance
        and $first._rank.status_rank == $second._rank.status_rank
        and $first._rank.authority_rank == $second._rank.authority_rank
        and $first._rank.review_due_rank == $second._rank.review_due_rank
        and $first._rank.verified_at_epoch == $second._rank.verified_at_epoch
        and $first._rank.created_epoch == $second._rank.created_epoch
    '
}

# --------------------------------------------------------------------------
# Parse arguments
# --------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --scope)
            [[ $# -lt 2 ]] && { wisdom_log ERROR "--scope requires a value"; usage; }
            SCOPE="$2"; shift 2 ;;
        --type)
            [[ $# -lt 2 ]] && { wisdom_log ERROR "--type requires a value"; usage; }
            TYPE="$2"; shift 2 ;;
        --tags)
            [[ $# -lt 2 ]] && { wisdom_log ERROR "--tags requires a value"; usage; }
            TAGS="$2"; shift 2 ;;
        --limit)
            [[ $# -lt 2 ]] && { wisdom_log ERROR "--limit requires a value"; usage; }
            LIMIT="$2"; shift 2 ;;
        --json)
            JSON_OUTPUT=true; shift ;;
        --min-score)
            [[ $# -lt 2 ]] && { wisdom_log ERROR "--min-score requires a value"; usage; }
            MIN_SCORE="$2"; shift 2 ;;
        --project-id)
            [[ $# -lt 2 ]] && { wisdom_log ERROR "--project-id requires a value"; usage; }
            PROJECT_ID="$2"; shift 2 ;;
        --authority)
            [[ $# -lt 2 ]] && { wisdom_log ERROR "--authority requires a value"; usage; }
            AUTHORITY_FILTER="$2"; shift 2 ;;
        --include-status)
            [[ $# -lt 2 ]] && { wisdom_log ERROR "--include-status requires a value"; usage; }
            INCLUDE_STATUS="$2"; shift 2 ;;
        --provenance)
            [[ $# -lt 2 ]] && { wisdom_log ERROR "--provenance requires a value"; usage; }
            PROVENANCE_FILTER="$2"; shift 2 ;;
        --origin-session)
            [[ $# -lt 2 ]] && { wisdom_log ERROR "--origin-session requires a value"; usage; }
            ORIGIN_SESSION_FILTER="$2"; shift 2 ;;
        --sort-authority)
            wisdom_log WARN "--sort-authority is deprecated; canonical ranking is now always applied"
            shift ;;
        --touch)
            TOUCH=true; shift ;;
        --help|-h)
            usage ;;
        -*)
            wisdom_log ERROR "Unknown option: $1"
            usage ;;
        *)
            if [[ -z "$QUERY" ]]; then
                QUERY="$1"; shift
            else
                wisdom_log ERROR "Unexpected argument: $1"
                usage
            fi
            ;;
    esac
done

query_hash=$(wisdom_hash_text "$QUERY") || query_hash=""
query_preview=$(wisdom_redact_preview "$QUERY") || query_preview=""

# QUERY is optional - if empty, show all entries
# No error if QUERY is empty

# Validate --scope
case "$SCOPE" in
    all|system|project|plan) ;;
    *) wisdom_log ERROR "Invalid scope: $SCOPE"; usage ;;
esac

# Validate --type if provided
if [[ -n "$TYPE" ]]; then
    local_type_valid=false
    for t in "${WISDOM_VALID_TYPES[@]}"; do
        if [[ "$TYPE" == "$t" ]]; then
            local_type_valid=true
            break
        fi
    done
    if [[ "$local_type_valid" == false ]]; then
        wisdom_log ERROR "Invalid type: $TYPE (valid: ${WISDOM_VALID_TYPES[*]})"
        usage
    fi
fi

# Validate --limit is a positive integer
if ! [[ "$LIMIT" =~ ^[0-9]+$ ]] || [[ "$LIMIT" -eq 0 ]]; then
    wisdom_log ERROR "--limit must be a positive integer"
    usage
fi

# Validate --min-score is a number if provided
if [[ -n "$MIN_SCORE" ]] && ! [[ "$MIN_SCORE" =~ ^[0-9]+$ ]]; then
    wisdom_log ERROR "--min-score must be a non-negative integer"
    usage
fi

if [[ -n "$AUTHORITY_FILTER" ]]; then
    validate_enum_value "$AUTHORITY_FILTER" "authority" "WISDOM_VALID_AUTHORITIES"
fi

if [[ -n "$PROVENANCE_FILTER" ]]; then
    validate_enum_value "$PROVENANCE_FILTER" "provenance" "WISDOM_VALID_PROVENANCES"
fi

declare -a VISIBLE_STATUSES=("active" "stale")
declare -a INCLUDE_STATUS_VALUES=()
if [[ -n "$INCLUDE_STATUS" ]]; then
    parse_csv_list "$INCLUDE_STATUS" INCLUDE_STATUS_VALUES
    if [[ ${#INCLUDE_STATUS_VALUES[@]} -eq 0 ]]; then
        wisdom_log ERROR "--include-status must include at least one status"
        usage
    fi

    for status_value in "${INCLUDE_STATUS_VALUES[@]}"; do
        validate_enum_value "$status_value" "status" "WISDOM_VALID_STATUSES"
        if ! array_contains "$status_value" "${VISIBLE_STATUSES[@]}"; then
            VISIBLE_STATUSES+=("$status_value")
        fi
    done
fi

# --------------------------------------------------------------------------
# Collect JSONL store files to search
# --------------------------------------------------------------------------
declare -a STORE_FILES=()

_add_file_if_exists() {
    local f="$1"
    if [[ -f "$f" && -s "$f" ]]; then
        STORE_FILES+=("$f")
    fi
}

case "$SCOPE" in
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
        if [[ -n "$PROJECT_ID" ]]; then
            _add_file_if_exists "${WISDOM_ROOT}/projects/${PROJECT_ID}.jsonl"
        elif [[ -d "${WISDOM_ROOT}/projects" ]]; then
            for f in "${WISDOM_ROOT}/projects"/*.jsonl; do
                _add_file_if_exists "$f"
            done
        fi
        ;;
    plan)
        if [[ -n "$PROJECT_ID" ]]; then
            _add_file_if_exists "${WISDOM_ROOT}/plans/${PROJECT_ID}.jsonl"
        elif [[ -d "${WISDOM_ROOT}/plans" ]]; then
            for f in "${WISDOM_ROOT}/plans"/*.jsonl; do
                _add_file_if_exists "$f"
            done
        fi
        ;;
esac

scanned_count=0
for store_file in "${STORE_FILES[@]}"; do
    local_file_count=$(wc -l < "$store_file" 2>/dev/null | tr -d ' ' || echo 0)
    scanned_count=$((scanned_count + local_file_count))
done

# If no store files found, exit with no results
if [[ ${#STORE_FILES[@]} -eq 0 ]]; then
    emit_wisdom_search_event "success" "no_results" 0
    if [[ "$JSON_OUTPUT" == true ]]; then
        echo "[]"
    else
        wisdom_log INFO "No matching entries found."
    fi
    exit 1
fi

# --------------------------------------------------------------------------
# Build jq filter for matching entries
# --------------------------------------------------------------------------
# Build jq select filter using safe --arg for query (literal substring matching)
# If query is empty, select all entries
if [[ -n "$QUERY" ]]; then
    JQ_FILTER="select(.body | ascii_downcase | contains(\$q | ascii_downcase))"
else
    JQ_FILTER="."
fi

# Add type filter
if [[ -n "$TYPE" ]]; then
    JQ_FILTER="${JQ_FILTER} | select(.type == \$type_filter)"
fi

# Add min-score filter
if [[ -n "$MIN_SCORE" ]]; then
    JQ_FILTER="${JQ_FILTER} | select((.quality_score // 0) >= ${MIN_SCORE})"
fi

# Add tag filter — all requested tags must exist (case-insensitive)
if [[ -n "$TAGS" ]]; then
    # Convert comma-separated tags to JSON array using jq
    TAGS_JSON=$(printf '%s' "$TAGS" | jq -R 'split(",") | map(gsub("^\\s+|\\s+$";""))')
    JQ_FILTER="${JQ_FILTER} | select((\$tags | map(ascii_downcase)) - (.tags // [] | map(ascii_downcase)) | length == 0)"
fi

# --------------------------------------------------------------------------
# Search all store files and collect results
# --------------------------------------------------------------------------
ALL_RESULTS=""
NOW_ISO=$(date -u +%Y-%m-%dT%H:%M:%SZ)

for store_file in "${STORE_FILES[@]}"; do
    # Run jq filter on each JSONL file; canonical filtering happens after normalization
    jq_args=(-c --arg q "$QUERY")
    [[ -n "$TYPE" ]] && jq_args+=(--arg type_filter "$TYPE")
    [[ -n "$TAGS" ]] && jq_args+=(--argjson tags "$TAGS_JSON")
    results=$(jq "${jq_args[@]}" "$JQ_FILTER" "$store_file" 2>/dev/null || true)

    while IFS= read -r raw_entry; do
        [[ -z "$raw_entry" ]] && continue

        normalized_entry=$(wisdom_normalize_record "$raw_entry" "$NOW_ISO") || continue

        entry_status=$(printf '%s' "$normalized_entry" | jq -r '.status')
        if ! array_contains "$entry_status" "${VISIBLE_STATUSES[@]}"; then
            continue
        fi

        entry_authority=$(printf '%s' "$normalized_entry" | jq -r '.authority')
        if [[ -n "$AUTHORITY_FILTER" && "$entry_authority" != "$AUTHORITY_FILTER" ]]; then
            continue
        fi

        entry_provenance=$(printf '%s' "$normalized_entry" | jq -r '.provenance')
        if [[ -n "$PROVENANCE_FILTER" && "$entry_provenance" != "$PROVENANCE_FILTER" ]]; then
            continue
        fi

        entry_origin_session=$(printf '%s' "$normalized_entry" | jq -r '.origin_session // ""')
        if [[ -n "$ORIGIN_SESSION_FILTER" && "$entry_origin_session" != "$ORIGIN_SESSION_FILTER" ]]; then
            continue
        fi

        relevance_score=$(printf '%s' "$normalized_entry" | jq -r --arg q "$QUERY" '
            if ($q | length) == 0 then 0
            else ((.body // "" | ascii_downcase | split($q | ascii_downcase) | length) - 1)
            end
        ')

        entry_with_meta=$(printf '%s' "$normalized_entry" | jq -c \
            --arg store_path "$store_file" \
            --argjson relevance "$relevance_score" \
            '. + {"_store_path": $store_path, "_relevance": $relevance}')
        ALL_RESULTS+="${entry_with_meta}"$'\n'
    done <<< "$results"
done

ALL_RESULTS=$(printf '%s' "$ALL_RESULTS" | sed '/^$/d')

matched_count=0
if [[ -n "$ALL_RESULTS" ]]; then
    matched_count=$(printf '%s' "$ALL_RESULTS" | sed '/^$/d' | wc -l | tr -d ' ' || echo 0)
fi

# If no results, exit
if [[ -z "$ALL_RESULTS" ]]; then
    emit_wisdom_search_event "success" "no_results" 0
    if [[ "$JSON_OUTPUT" == true ]]; then
        echo "[]"
    else
        wisdom_log INFO "No matching entries found."
    fi
    exit 1
fi

# --------------------------------------------------------------------------
# Sort using canonical ranking: relevance, status, authority, review_due,
# verified_at, created, id; then apply limit.
# --------------------------------------------------------------------------
RANKED_RESULTS=""
while IFS= read -r entry_json; do
    [[ -z "$entry_json" ]] && continue
    entry_relevance=$(printf '%s' "$entry_json" | jq -r '._relevance // 0')
    canonical_entry=$(printf '%s' "$entry_json" | jq -c 'del(._store_path, ._relevance)')
    entry_rank=$(wisdom_rank_entry "$canonical_entry" "$entry_relevance" "$NOW_ISO") || continue
    ranked_entry=$(printf '%s' "$entry_json" | jq -c --argjson rank "$entry_rank" '. + {"_rank": $rank}')
    RANKED_RESULTS+="${ranked_entry}"$'\n'
done <<< "$ALL_RESULTS"

SORTED_RESULTS=$(printf '%s\n' "$RANKED_RESULTS" | jq -s 'sort_by(._rank.sort_key)')

# --------------------------------------------------------------------------
# UNKNOWN handling: top two non-superseded, equal-rank contradictory entries
# should not produce an arbitrary winner.
# --------------------------------------------------------------------------
TOP_TWO_NON_SUPERSEDED=$(printf '%s' "$SORTED_RESULTS" | jq -c '[.[] | select(.status != "superseded")][0:2]')
TOP_TWO_COUNT=$(printf '%s' "$TOP_TWO_NON_SUPERSEDED" | jq 'length')

if [[ "$TOP_TWO_COUNT" -eq 2 ]]; then
    first_ranked=$(printf '%s' "$TOP_TWO_NON_SUPERSEDED" | jq -c '.[0]')
    second_ranked=$(printf '%s' "$TOP_TWO_NON_SUPERSEDED" | jq -c '.[1]')

    first_entry=$(printf '%s' "$first_ranked" | jq -c 'del(._store_path, ._relevance, ._rank)')
    second_entry=$(printf '%s' "$second_ranked" | jq -c 'del(._store_path, ._relevance, ._rank)')

    if [[ "$(entries_share_conflict_rank "$first_ranked" "$second_ranked")" == "true" ]] && [[ "$(entry_has_mutual_contradiction "$first_entry" "$second_entry")" == "true" ]]; then
        if contradiction_result=$(wisdom_check_contradiction "$first_entry" "$second_entry"); then
            wisdom_log WARN "Equal-rank contradictory wisdom detected; returning ${contradiction_result}"
            emit_wisdom_search_event "success" "conflict_unknown" 0
            if [[ "$JSON_OUTPUT" == true ]]; then
                printf '%s\n' '"UNKNOWN"'
            else
                printf 'UNKNOWN\n'
            fi
            exit 0
        fi
    fi
fi

SORTED_LIMITED=$(printf '%s' "$SORTED_RESULTS" | jq '.[0:'"$LIMIT"']')

# Get count of results
RESULT_COUNT=$(printf '%s' "$SORTED_LIMITED" | jq 'length')

if [[ "$RESULT_COUNT" -eq 0 ]]; then
    emit_wisdom_search_event "success" "no_results" 0
    if [[ "$JSON_OUTPUT" == true ]]; then
        echo "[]"
    else
        wisdom_log INFO "No matching entries found."
    fi
    exit 1
fi

emit_wisdom_search_event "success" "" "$RESULT_COUNT"

# --------------------------------------------------------------------------
# Access tracking: bump accessed+1 and set last_accessed for matched entries
# --------------------------------------------------------------------------
if [[ "$TOUCH" == true ]]; then
    NOW_ISO=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    for i in $(seq 0 $((RESULT_COUNT - 1))); do
        entry_json=$(printf '%s' "$SORTED_LIMITED" | jq -c ".[$i]")
        entry_id=$(printf '%s' "$entry_json" | jq -r '.id')
        store_path=$(printf '%s' "$entry_json" | jq -r '._store_path')

        updated_json=$(printf '%s' "$entry_json" | jq -c --arg now "$NOW_ISO" '
            del(._store_path, ._relevance, ._rank)
            | .accessed = ((.accessed // 0) + 1)
            | .last_accessed = $now
        ')

        wisdom_update_entry "$entry_id" "$store_path" "$updated_json" 2>/dev/null || true
    done
fi

# --------------------------------------------------------------------------
# Output results
# --------------------------------------------------------------------------
if [[ "$JSON_OUTPUT" == true ]]; then
    # Strip _store_path from output
    printf '%s' "$SORTED_LIMITED" | jq '[.[] | del(._store_path, ._relevance, ._rank)]'
else
    # Human-readable output
    for i in $(seq 0 $((RESULT_COUNT - 1))); do
        entry_json=$(printf '%s' "$SORTED_LIMITED" | jq -c ".[$i]")

        entry_id=$(printf '%s' "$entry_json" | jq -r '.id')
        entry_type=$(printf '%s' "$entry_json" | jq -r '.type')
        entry_scope=$(printf '%s' "$entry_json" | jq -r '.scope')
        entry_score=$(printf '%s' "$entry_json" | jq -r '.quality_score // 0')
        entry_accessed=$(printf '%s' "$entry_json" | jq -r '(.accessed // 0) | tostring')
        entry_tags=$(printf '%s' "$entry_json" | jq -r '(.tags // []) | join(", ")')
        entry_body=$(printf '%s' "$entry_json" | jq -r '.body // ""')

        # Truncate body to 200 chars
        if [[ ${#entry_body} -gt 200 ]]; then
            entry_body="${entry_body:0:200}..."
        fi

        printf '[%s] type=%s scope=%s score=%s accessed=%s\n' \
            "$entry_id" "$entry_type" "$entry_scope" "$entry_score" "$entry_accessed"
        printf 'tags: %s\n' "${entry_tags:-none}"
        printf '%s\n' "$entry_body"
        printf -- '---\n'
    done
fi

exit 0
