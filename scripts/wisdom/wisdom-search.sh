#!/usr/bin/env bash
set -euo pipefail

# wisdom-search.sh — Search JSONL wisdom stores with filtering, sorting, and access tracking
# Usage: wisdom-search.sh QUERY [OPTIONS]

# Source shared library
source "$(dirname "$0")/wisdom-common.sh"
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
  --help, -h             Show this help

Exit codes:
  0  Found results
  1  No results found
  2  Bad arguments
EOF
    exit 2
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

# QUERY is required
if [[ -z "$QUERY" ]]; then
    wisdom_log ERROR "QUERY is required"
    usage
fi

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

# If no store files found, exit with no results
if [[ ${#STORE_FILES[@]} -eq 0 ]]; then
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
JQ_FILTER="select(.body | ascii_downcase | contains(\$q | ascii_downcase))"

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

for store_file in "${STORE_FILES[@]}"; do
    # Run jq filter on each JSONL file, add _store_path for access tracking
    store_escaped=$(printf '%s' "$store_file" | jq -Rs .)
    # Build jq args array for safe variable passing (no eval)
    jq_args=(-c --arg q "$QUERY")
    [[ -n "$TYPE" ]] && jq_args+=(--arg type_filter "$TYPE")
    [[ -n "$TAGS" ]] && jq_args+=(--argjson tags "$TAGS_JSON")
    results=$(jq "${jq_args[@]}" "${JQ_FILTER} | . + {\"_store_path\": ${store_escaped}}" "$store_file" 2>/dev/null || true)
    if [[ -n "$results" ]]; then
        ALL_RESULTS+="${results}"$'\n'
    fi
done

ALL_RESULTS=$(printf '%s' "$ALL_RESULTS" | sed '/^$/d')

# If no results, exit
if [[ -z "$ALL_RESULTS" ]]; then
    if [[ "$JSON_OUTPUT" == true ]]; then
        echo "[]"
    else
        wisdom_log INFO "No matching entries found."
    fi
    exit 1
fi

# --------------------------------------------------------------------------
# Sort by quality_score desc, then accessed desc; apply limit
# --------------------------------------------------------------------------
SORTED_LIMITED=$(printf '%s\n' "$ALL_RESULTS" | jq -s '
    sort_by(-(.quality_score // 0), -(.accessed // 0))
    | .[0:'"$LIMIT"']
')

# Get count of results
RESULT_COUNT=$(printf '%s' "$SORTED_LIMITED" | jq 'length')

if [[ "$RESULT_COUNT" -eq 0 ]]; then
    if [[ "$JSON_OUTPUT" == true ]]; then
        echo "[]"
    else
        wisdom_log INFO "No matching entries found."
    fi
    exit 1
fi

# --------------------------------------------------------------------------
# Access tracking: bump accessed+1 and set last_accessed for matched entries
# --------------------------------------------------------------------------
NOW_ISO=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Iterate over each result and update its store
for i in $(seq 0 $((RESULT_COUNT - 1))); do
    entry_json=$(printf '%s' "$SORTED_LIMITED" | jq -c ".[$i]")
    entry_id=$(printf '%s' "$entry_json" | jq -r '.id')
    store_path=$(printf '%s' "$entry_json" | jq -r '._store_path')

    # Build updated entry: bump accessed, set last_accessed, remove _store_path
    updated_json=$(printf '%s' "$entry_json" | jq -c --arg now "$NOW_ISO" "
        del(._store_path)
        | .accessed = ((.accessed // 0) + 1)
        | .last_accessed = \$now
    ")

    wisdom_update_entry "$entry_id" "$store_path" "$updated_json" 2>/dev/null || true
done

# --------------------------------------------------------------------------
# Output results
# --------------------------------------------------------------------------
if [[ "$JSON_OUTPUT" == true ]]; then
    # Strip _store_path from output
    printf '%s' "$SORTED_LIMITED" | jq '[.[] | del(._store_path)]'
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
