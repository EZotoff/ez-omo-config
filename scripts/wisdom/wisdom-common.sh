# wisdom-common.sh — Shared library for wisdom subsystem
# Source guard
[[ -n "${_WISDOM_COMMON_LOADED:-}" ]] && return 0
_WISDOM_COMMON_LOADED=1

# Constants
WISDOM_ROOT="${HOME}/.sisyphus/wisdom"
WISDOM_SCRIPTS="${HOME}/.sisyphus/scripts"
WISDOM_VALID_TYPES=("gotcha" "pattern" "fact" "decision" "warning")
WISDOM_VALID_SCOPES=("system" "project" "plan")
WISDOM_VALID_AUTHORITIES=("candidate" "verified" "published")
WISDOM_VALID_STATUSES=("active" "stale" "superseded" "retracted")
WISDOM_VALID_PROVENANCES=("closeout" "nomination" "manual" "manifest-import" "migration" "publish-export" "compat-shim")
WISDOM_METADATA_KEYS=(
    "owner"
    "sensitivity"
    "validation_method"
    "last_verified"
    "freshness_days"
    "legacy_manifest_id"
    "legacy_manifest_path"
    "legacy_authority"
    "source_kind"
    "published_artifacts"
)

# Global error flag for wisdom_log ERROR
_WISDOM_ERROR=0

# Canonical Wisdom Contract Fields (additive beyond the base schema)
# authority: candidate | verified | published
# status: active | stale | superseded | retracted
# provenance: closeout | nomination | manual | manifest-import | migration | publish-export | compat-shim
# origin_session: OpenCode session ID where this was captured (null allowed)
# verified_at: ISO-8601 timestamp of last verification (required for verified/published)
# review_due: ISO-8601 timestamp for scheduled review (null if none)
# superseded_by: ID of the entry that replaces this one (required when status=superseded)
# contradicts: Array of conflicting Wisdom IDs (default: [])
# metadata: Fixed object with canonical keys defined in WISDOM_METADATA_KEYS

# --------------------------------------------------------------------------
# 1. wisdom_generate_id — Generate a unique entry ID
#    Format: YYYYMMDD-HHMMSS-XXXX (4 random lowercase alphanumeric)
# --------------------------------------------------------------------------
wisdom_generate_id() {
    local ts suffix
    ts=$(date +%Y%m%d-%H%M%S)
    suffix=$(dd if=/dev/urandom bs=1 count=32 2>/dev/null | base64 | tr -dc 'a-z0-9' | cut -c1-4)
    printf '%s-%s\n' "$ts" "$suffix"
}

# --------------------------------------------------------------------------
# 2. wisdom_get_store_path — Resolve JSONL store file path for a scope
#    Args: $1=scope, $2=project_id (required for project/plan)
#    Returns: path on stdout, 1 on error
# --------------------------------------------------------------------------
wisdom_get_store_path() {
    local scope="${1:-}"
    local project_id="${2:-}"

    # Validate scope
    local valid=false
    local s
    for s in "${WISDOM_VALID_SCOPES[@]}"; do
        if [[ "$scope" == "$s" ]]; then
            valid=true
            break
        fi
    done
    if [[ "$valid" == false ]]; then
        echo "Error: invalid scope '$scope' (valid: ${WISDOM_VALID_SCOPES[*]})" >&2
        return 1
    fi

    # Validate project_id requirement
    if [[ "$scope" == "project" || "$scope" == "plan" ]] && [[ -z "$project_id" ]]; then
        echo "Error: scope '$scope' requires a project_id argument" >&2
        return 1
    fi

    case "$scope" in
        system)  printf '%s\n' "${WISDOM_ROOT}/system.jsonl" ;;
        project) printf '%s\n' "${WISDOM_ROOT}/projects/${project_id}.jsonl" ;;
        plan)    printf '%s\n' "${WISDOM_ROOT}/plans/${project_id}.jsonl" ;;
    esac
    return 0
}

# --------------------------------------------------------------------------
# 3. wisdom_init_store — Ensure store file and parent dirs exist
#    Args: $1=path
# --------------------------------------------------------------------------
wisdom_init_store() {
    local path="$1"
    mkdir -p "$(dirname "$path")"
    touch "$path"
    return 0
}

# --------------------------------------------------------------------------
# 4. wisdom_read_entry — Find an entry by ID in a JSONL store
#    Args: $1=id, $2=store_path
#    Outputs: full JSON line to stdout. Returns 1 if not found.
# --------------------------------------------------------------------------
wisdom_read_entry() {
    local id="$1"
    local store_path="$2"

    local result
    result=$(jq -c --arg id "$id" 'select(.id == $id)' "$store_path" 2>/dev/null)

    if [[ -z "$result" ]]; then
        return 1
    fi
    printf '%s\n' "$result"
    return 0
}

# --------------------------------------------------------------------------
# 5. wisdom_append_entry — Atomically append a JSON line to a store
#    Args: $1=json_line, $2=store_path
#    Returns: 0 on success, 1 on invalid JSON, 2 on write error
# --------------------------------------------------------------------------
wisdom_append_entry() {
    local json_line="$1"
    local store_path="$2"

    # Validate JSON
    if ! printf '%s' "$json_line" | jq empty 2>/dev/null; then
        echo "Error: invalid JSON in append" >&2
        return 1
    fi

    # Use atomic append with flock-based locking
    if ! wisdom_atomic_append "$store_path" "$json_line"; then
        echo "Error: atomic append failed" >&2
        return 2
    fi

    return 0
}

# --------------------------------------------------------------------------
# 6. wisdom_remove_entry — Atomically remove an entry by ID
#    Args: $1=id, $2=store_path
#    Returns: 0 on success, 1 if not found
# --------------------------------------------------------------------------
wisdom_remove_entry() {
    local id="$1"
    local store_path="$2"

    # Check entry exists first
    if ! wisdom_read_entry "$id" "$store_path" >/dev/null 2>&1; then
        echo "Error: entry '$id' not found" >&2
        return 1
    fi

    local tmp
    tmp=$(mktemp "${store_path}.tmp.XXXXXX")
    jq -c --arg id "$id" 'select(.id != $id)' "$store_path" > "$tmp"
    mv -f "$tmp" "$store_path"
    return 0
}

# --------------------------------------------------------------------------
# 7. wisdom_update_entry — Atomically replace an entry by ID
#    Args: $1=id, $2=store_path, $3=updated_json
#    Returns: 0 on success, 1 if not found
# --------------------------------------------------------------------------
wisdom_update_entry() {
    local id="$1"
    local store_path="$2"
    local updated_json="$3"

    # Check entry exists
    if ! wisdom_read_entry "$id" "$store_path" >/dev/null 2>&1; then
        echo "Error: entry '$id' not found for update" >&2
        return 1
    fi

    # Atomic: filter out old entry + append updated
    local tmp
    tmp=$(mktemp "${store_path}.tmp.XXXXXX")
    { jq -c --arg id "$id" 'select(.id != $id)' "$store_path"; printf '%s\n' "$updated_json"; } > "$tmp"
    mv -f "$tmp" "$store_path"
    return 0
}

# --------------------------------------------------------------------------
# 8. wisdom_escape_json — Escape a string for safe JSON embedding
#    Args: $1=string
#    Outputs: JSON-escaped string WITH surrounding quotes
# --------------------------------------------------------------------------
wisdom_escape_json() {
    printf '%s' "$1" | jq -Rs .
}

# --------------------------------------------------------------------------
# 9. wisdom_classify_type — Keyword-based type classification
#     Args: $1=content text
#     Outputs: type string to stdout
# --------------------------------------------------------------------------
wisdom_classify_type() {
    local lower="${1,,}"

    if [[ "$lower" =~ (gotcha|watch[[:space:]]+out|careful|beware|never|avoid|don\'t|do[[:space:]]+not|trap|pitfall) ]]; then
        printf 'gotcha'
    elif [[ "$lower" =~ (pattern|convention|always|standard|approach|practice|prefer) ]]; then
        printf 'pattern'
    elif [[ "$lower" =~ (decided|chose|decision|agreed|selected|picked) ]]; then
        printf 'decision'
    elif [[ "$lower" =~ (warning|deprecated|broken|bug|issue|fails|error) ]]; then
        printf 'warning'
    else
        printf 'fact'
    fi
}

# --------------------------------------------------------------------------
# 10. wisdom_check_secret — Detect secrets/credentials in content
#     Args: $1=content
#     Returns: 0 if SAFE (no secret), 1 if secret detected (BLOCKED)
# --------------------------------------------------------------------------
wisdom_check_secret() {
    local content="$1"

    # Generic credential assignment patterns
    if [[ "$content" =~ (API_KEY|APIKEY|API_SECRET|SECRET_KEY|SECRET|PASSWORD|PASSWD|PRIVATE_KEY|ACCESS_TOKEN|AUTH_TOKEN)=[^[:space:]]+ ]]; then
        echo "Secret detected: credential assignment pattern" >&2
        return 1
    fi

    # OpenAI-style keys
    if [[ "$content" =~ sk-[a-zA-Z0-9]{20,} ]]; then
        echo "Secret detected: OpenAI-style API key" >&2
        return 1
    fi

    # GitHub personal access tokens
    if [[ "$content" =~ ghp_[a-zA-Z0-9]{36} ]]; then
        echo "Secret detected: GitHub personal access token" >&2
        return 1
    fi

    # Slack bot tokens
    if [[ "$content" =~ xoxb-[a-zA-Z0-9-]{24,} ]]; then
        echo "Secret detected: Slack bot token" >&2
        return 1
    fi

    # Private keys
    if [[ "$content" =~ -----BEGIN.*PRIVATE\ KEY----- ]]; then
        echo "Secret detected: private key" >&2
        return 1
    fi

    # Generic password assignment (exclude process.env. and file paths)
    # Check for password pattern but NOT preceded by process.env. or in file paths
    if [[ "$content" =~ [Pp]assword[[:space:]]*[=:][[:space:]]*[^[:space:]]{8,} ]]; then
        # Exclude if it's a process.env reference or file path
        if ! [[ "$content" =~ process\.env\.[Pp]assword ]] && ! [[ "$content" =~ /[a-zA-Z0-9_/]*[Pp]assword ]]; then
            echo "Secret detected: password assignment" >&2
            return 1
        fi
    fi

    # Generic token assignment (exclude process.env. and file paths)
    if [[ "$content" =~ [Tt]oken[[:space:]]*[=:][[:space:]]*[^[:space:]]{8,} ]]; then
        if ! [[ "$content" =~ process\.env\.[Tt]oken ]] && ! [[ "$content" =~ /[a-zA-Z0-9_/]*[Tt]oken ]]; then
            echo "Secret detected: token assignment" >&2
            return 1
        fi
    fi

    return 0
}

# --------------------------------------------------------------------------
# 11. wisdom_require_jq — Check that jq is available
#     Returns: 0 if available, 1 if missing
# --------------------------------------------------------------------------
wisdom_require_jq() {
    if ! command -v jq >/dev/null 2>&1; then
        echo "Error: jq is required but not found. Install jq to use wisdom." >&2
        return 1
    fi
    return 0
}

# --------------------------------------------------------------------------
# 12. wisdom_log — Log a message to stderr
#     Args: $1=level (INFO|WARN|ERROR), $2=message
# --------------------------------------------------------------------------
wisdom_log() {
    local level="$1"
    local message="$2"
    printf '[%s] %s\n' "$level" "$message" >&2
    if [[ "$level" == "ERROR" ]]; then
        _WISDOM_ERROR=1
    fi
}

# --------------------------------------------------------------------------
# 13. wisdom_field_with_default — Extract field from JSONL with default
#     Args: $1=field_name, $2=json_line, $3=default_value
#     Outputs: field value or default if missing/null
# --------------------------------------------------------------------------
wisdom_field_with_default() {
  local field="$1"
  local json_line="$2"
  local default="$3"
  local value
  value=$(echo "$json_line" | jq -r ".$field // empty" 2>/dev/null)
  if [[ -z "$value" || "$value" == "null" ]]; then
    echo "$default"
  else
    echo "$value"
  fi
}

# --------------------------------------------------------------------------
# 15. wisdom_array_to_json — Convert string args to JSON array
#     Args: $@=values
#     Outputs: compact JSON array to stdout
# --------------------------------------------------------------------------
wisdom_array_to_json() {
    if [[ $# -eq 0 ]]; then
        printf '[]\n'
        return 0
    fi

    printf '%s\n' "$@" | jq -R . | jq -sc .
}

# --------------------------------------------------------------------------
# 16. wisdom_normalize_authority — Map legacy authority values to canonical
#     Args: $1=authority_string
#     Outputs: canonical authority string to stdout
# --------------------------------------------------------------------------
wisdom_normalize_authority() {
    local authority="${1:-}"

    case "$authority" in
        ""|null|wisdom|stale|superseded) printf 'candidate\n' ;;
        verified)                         printf 'verified\n' ;;
        manifest)                         printf 'published\n' ;;
        candidate|published)              printf '%s\n' "$authority" ;;
        *)                                printf '%s\n' "$authority" ;;
    esac
}

# --------------------------------------------------------------------------
# 17. wisdom_normalize_status — Map legacy or missing status to canonical
#     Args: $1=status, $2=authority, $3=review_due, $4=now_iso (optional)
#     Outputs: canonical status string to stdout
# --------------------------------------------------------------------------
wisdom_normalize_status() {
    local status="${1:-}"
    local authority="${2:-}"
    local review_due="${3:-}"
    local now_iso="${4:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
    local is_overdue

    case "$authority" in
        stale)
            printf 'stale\n'
            return 0
            ;;
        superseded)
            printf 'superseded\n'
            return 0
            ;;
    esac

    if [[ -z "$status" || "$status" == "null" ]]; then
        if [[ -n "$review_due" && "$review_due" != "null" ]]; then
            is_overdue=$(jq -nr --arg review_due "$review_due" --arg now "$now_iso" '
                try (($review_due | fromdateiso8601) < ($now | fromdateiso8601)) catch false
            ')
            if [[ "$is_overdue" == "true" ]]; then
                printf 'stale\n'
                return 0
            fi
        fi
        printf 'active\n'
        return 0
    fi

    printf '%s\n' "$status"
}

# --------------------------------------------------------------------------
# 18. Legacy-to-canonical mapping table
#
#     Legacy input         Canonical normalization
#     ------------------   -----------------------------------------------
#     missing authority    authority=candidate, provenance=migration,
#                          metadata.legacy_authority=null
#     authority=wisdom     authority=candidate, provenance=migration,
#                          metadata.legacy_authority=wisdom
#     authority=verified   authority=verified, preserve/backfill verified_at
#     authority=manifest   authority=published, provenance=manifest-import,
#                          metadata.legacy_authority=manifest
#     authority=stale      authority=candidate, status=stale,
#                          metadata.legacy_authority=stale
#     authority=superseded authority=candidate, status=superseded,
#                          metadata.legacy_authority=superseded
#     missing status       status=active unless review_due is past, then stale
#     missing origin       origin_session=null
# --------------------------------------------------------------------------

# --------------------------------------------------------------------------
# 19. wisdom_build_metadata — Build canonical metadata object
#     Args: $1=record_json, $2=legacy_authority_override (optional)
#     Outputs: compact metadata JSON object to stdout
# --------------------------------------------------------------------------
wisdom_build_metadata() {
    local record_json="${1:-{}}"
    local legacy_authority="${2:-}"
    local legacy_authority_json="null"

    if [[ -n "$legacy_authority" && "$legacy_authority" != "null" ]]; then
        legacy_authority_json=$(wisdom_escape_json "$legacy_authority")
    fi

    printf '%s' "$record_json" | jq -c --argjson legacy_authority "$legacy_authority_json" '
        . as $record
        | ($record.metadata | if type == "object" then . else {} end) as $metadata
        | {
            owner: ($metadata.owner // null),
            sensitivity: ($metadata.sensitivity // null),
            validation_method: ($metadata.validation_method // null),
            last_verified: ($metadata.last_verified // null),
            freshness_days: ($metadata.freshness_days // null),
            legacy_manifest_id: ($metadata.legacy_manifest_id // $record.legacy_manifest_id // $record.manifest_id // null),
            legacy_manifest_path: ($metadata.legacy_manifest_path // $record.legacy_manifest_path // $record.manifest_path // null),
            legacy_authority: ($legacy_authority // $metadata.legacy_authority // null),
            source_kind: ($metadata.source_kind // $record.source_kind // null),
            published_artifacts: (($metadata.published_artifacts // $record.published_artifacts // []) | if type == "array" then . else [] end)
        }
    '
}

# --------------------------------------------------------------------------
# 20. wisdom_rank_entry — Compute canonical ranking payload for an entry
#     Args: $1=entry_json, $2=relevance_score (optional), $3=now_iso (optional)
#     Outputs: compact JSON object with rank fields and sort_key
# --------------------------------------------------------------------------
wisdom_rank_entry() {
    local entry_json="$1"
    local relevance="${2:-0}"
    local now_iso="${3:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
    local normalized

    normalized=$(wisdom_normalize_record "$entry_json" "$now_iso") || return 1

    printf '%s' "$normalized" | jq -c --arg relevance "$relevance" --arg now "$now_iso" '
        def status_rank:
            if . == "active" then 4
            elif . == "stale" then 3
            elif . == "superseded" then 2
            elif . == "retracted" then 1
            else 0 end;
        def authority_rank:
            if . == "published" then 3
            elif . == "verified" then 2
            elif . == "candidate" then 1
            else 0 end;
        def review_due_rank:
            if . == null then 1
            else (try (if (. | fromdateiso8601) >= ($now | fromdateiso8601) then 3 else 2 end) catch 1)
            end;
        def epoch_or_zero:
            if . == null then 0 else (try (fromdateiso8601) catch 0) end;
        ($relevance | tonumber? // 0) as $relevance_num
        | {
            relevance: $relevance_num,
            status_rank: (.status | status_rank),
            authority_rank: (.authority | authority_rank),
            review_due_rank: (.review_due | review_due_rank),
            verified_at_epoch: (.verified_at | epoch_or_zero),
            created_epoch: (.created | epoch_or_zero),
            id: (.id // ""),
            sort_key: [
                -$relevance_num,
                -(.status | status_rank),
                -(.authority | authority_rank),
                -(.review_due | review_due_rank),
                -(.verified_at | epoch_or_zero),
                -(.created | epoch_or_zero),
                (.id // "")
            ]
        }
    '
}

# --------------------------------------------------------------------------
# 21. wisdom_compare_entries — Compare two entries using jq sort semantics
#     Args: $1=left_entry_json, $2=right_entry_json,
#           $3=left_relevance (optional), $4=right_relevance (optional),
#           $5=now_iso (optional)
#     Outputs: -1 if left sorts first, 1 if right sorts first, 0 if tied
# --------------------------------------------------------------------------
wisdom_compare_entries() {
    local left_entry="$1"
    local right_entry="$2"
    local left_relevance="${3:-0}"
    local right_relevance="${4:-0}"
    local now_iso="${5:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
    local left_rank right_rank

    left_rank=$(wisdom_rank_entry "$left_entry" "$left_relevance" "$now_iso") || return 1
    right_rank=$(wisdom_rank_entry "$right_entry" "$right_relevance" "$now_iso") || return 1

    jq -nr --argjson left "$left_rank" --argjson right "$right_rank" '
        if $left.sort_key < $right.sort_key then -1
        elif $left.sort_key > $right.sort_key then 1
        else 0
        end
    '
}

# --------------------------------------------------------------------------
# 22. wisdom_check_contradiction — Detect equal-level contradictory matches
#     Args: $1=first_entry_json, $2=second_entry_json
#     Outputs: UNKNOWN on conflict, nothing otherwise
#     Returns: 0 on contradiction, 1 when no contradiction is detected
# --------------------------------------------------------------------------
wisdom_check_contradiction() {
    local first_entry="$1"
    local second_entry="$2"
    local first_normalized second_normalized
    local result

    first_normalized=$(wisdom_normalize_record "$first_entry") || return 1
    second_normalized=$(wisdom_normalize_record "$second_entry") || return 1

    result=$(jq -nr --argjson first "$first_normalized" --argjson second "$second_normalized" '
        def normalize_text:
            if . == null then ""
            else ascii_downcase | gsub("[^a-z0-9]+"; " ") | gsub("^ +| +$"; "")
            end;
        def topic_key($entry): (($entry.title // $entry.body // "") | normalize_text);
        def body_key($entry): (($entry.body // "") | normalize_text);
        def explicitly_conflicting($left; $right):
            (($left.contradicts // []) | index($right.id)) != null
            or (($right.contradicts // []) | index($left.id)) != null;
        if $first.status == "superseded" or $second.status == "superseded" then empty
        elif topic_key($first) == "" or topic_key($first) != topic_key($second) then empty
        elif $first.status != $second.status or $first.authority != $second.authority then empty
        elif body_key($first) == body_key($second) then empty
        elif explicitly_conflicting($first; $second) or body_key($first) != body_key($second) then "UNKNOWN"
        else empty
        end
    ')

    if [[ -n "$result" ]]; then
        printf '%s\n' "$result"
        return 0
    fi

    return 1
}

# --------------------------------------------------------------------------
# 23. wisdom_normalize_record — Normalize a legacy or canonical record
#     Args: $1=record_json
#     Outputs: compact canonical JSON record to stdout
# --------------------------------------------------------------------------
wisdom_normalize_record() {
    local json_string="$1"
    local now_iso="${2:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
    local raw_authority raw_status raw_review_due raw_provenance
    local normalized_authority normalized_status normalized_provenance
    local metadata_json legacy_authority has_canonical_shape

    if ! printf '%s' "$json_string" | jq empty 2>/dev/null; then
        echo "Error: not valid JSON" >&2
        return 1
    fi

    raw_authority=$(printf '%s' "$json_string" | jq -r '.authority // empty')
    raw_status=$(printf '%s' "$json_string" | jq -r '.status // empty')
    raw_review_due=$(printf '%s' "$json_string" | jq -r '.review_due // empty')
    raw_provenance=$(printf '%s' "$json_string" | jq -r '.provenance // empty')
    has_canonical_shape=$(printf '%s' "$json_string" | jq -r '
        has("status") or has("provenance") or has("metadata") or has("title") or has("origin_session") or has("contradicts")
    ')

    normalized_authority=$(wisdom_normalize_authority "$raw_authority")
    normalized_status=$(wisdom_normalize_status "$raw_status" "$raw_authority" "$raw_review_due" "$now_iso")

    legacy_authority=$(printf '%s' "$json_string" | jq -r '.metadata.legacy_authority // empty')
    if [[ -z "$legacy_authority" ]]; then
        case "$raw_authority" in
            ""|null)
                legacy_authority=""
                ;;
            candidate|verified|published)
                legacy_authority=""
                ;;
            *)
                legacy_authority="$raw_authority"
                ;;
        esac
    fi

    case "$raw_provenance" in
        closeout|nomination|manual|manifest-import|migration|publish-export|compat-shim)
            normalized_provenance="$raw_provenance"
            ;;
        *)
            case "$raw_authority" in
                manifest)
                    normalized_provenance="manifest-import"
                    ;;
                ""|null|wisdom|stale|superseded)
                    normalized_provenance="migration"
                    ;;
                verified)
                    if [[ "$has_canonical_shape" == "true" ]]; then
                        normalized_provenance="manual"
                    else
                        normalized_provenance="migration"
                    fi
                    ;;
                *)
                    normalized_provenance="manual"
                    ;;
            esac
            ;;
    esac

    metadata_json=$(wisdom_build_metadata "$json_string" "$legacy_authority") || return 1

    printf '%s' "$json_string" | jq -c \
        --arg authority "$normalized_authority" \
        --arg status "$normalized_status" \
        --arg provenance "$normalized_provenance" \
        --argjson metadata "$metadata_json" '
        . as $record
        | {
            id: ($record.id // null),
            type: ($record.type // null),
            scope: ($record.scope // null),
            title: ($record.title // null),
            tags: (
                ($record.tags // [])
                | if type == "array" then
                    map(select(type == "string") | ascii_downcase)
                    | unique
                  elif type == "string" then
                    split(",")
                    | map(gsub("^\\s+|\\s+$"; "") | ascii_downcase)
                    | map(select(length > 0))
                    | unique
                  else [] end
            ),
            body: ($record.body // null),
            authority: $authority,
            status: $status,
            provenance: $provenance,
            origin_session: (($record.origin_session // null) | if . == "" then null else . end),
            verified_at: (
                if ($authority == "verified" or $authority == "published") then
                    (($record.verified_at // $metadata.last_verified // null) | if . == "" then null else . end)
                else null end
            ),
            review_due: (($record.review_due // null) | if . == "" then null else . end),
            superseded_by: (
                if $status == "superseded" then
                    (($record.superseded_by // null) | if . == "" then null else . end)
                else null end
            ),
            contradicts: (($record.contradicts // []) | if type == "array" then map(select(type == "string")) | unique else [] end),
            metadata: $metadata,
            created: ($record.created // null),
            accessed: ($record.accessed // 0),
            last_accessed: ($record.last_accessed // ""),
            source: (($record.source // null) | if . == "" then null else . end),
            quality_score: ($record.quality_score // null)
        }
    '
}

# --------------------------------------------------------------------------
# 24. wisdom_validate_canonical — Validate the canonical Wisdom schema
#     Args: $1=record_json
#     Returns: 0 if valid, 1 if invalid (errors on stderr)
# --------------------------------------------------------------------------
wisdom_validate_canonical() {
    local json_string="$1"
    local now_iso="${2:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
    local valid_types_json valid_scopes_json valid_authorities_json
    local valid_statuses_json valid_provenances_json metadata_keys_json
    local errors warning

    if ! printf '%s' "$json_string" | jq empty 2>/dev/null; then
        echo "Error: not valid JSON" >&2
        return 1
    fi

    valid_types_json=$(wisdom_array_to_json "${WISDOM_VALID_TYPES[@]}")
    valid_scopes_json=$(wisdom_array_to_json "${WISDOM_VALID_SCOPES[@]}")
    valid_authorities_json=$(wisdom_array_to_json "${WISDOM_VALID_AUTHORITIES[@]}")
    valid_statuses_json=$(wisdom_array_to_json "${WISDOM_VALID_STATUSES[@]}")
    valid_provenances_json=$(wisdom_array_to_json "${WISDOM_VALID_PROVENANCES[@]}")
    metadata_keys_json=$(wisdom_array_to_json "${WISDOM_METADATA_KEYS[@]}")

    errors=$(printf '%s' "$json_string" | jq -r \
        --argjson valid_types "$valid_types_json" \
        --argjson valid_scopes "$valid_scopes_json" \
        --argjson valid_authorities "$valid_authorities_json" \
        --argjson valid_statuses "$valid_statuses_json" \
        --argjson valid_provenances "$valid_provenances_json" \
        --argjson metadata_keys "$metadata_keys_json" '
        def string_or_null: . == null or type == "string";
        def number_or_null: . == null or type == "number";
        def array_of_strings: type == "array" and all(.[]?; type == "string");
        def iso8601_or_null:
            . == null or (type == "string" and (try (fromdateiso8601 | type) catch null) != null);
        . as $record
        | [
            (if $record.id == null then "missing required field: id" else empty end),
            (if $record.type == null then "missing required field: type" else empty end),
            (if $record.scope == null then "missing required field: scope" else empty end),
            (if $record.body == null then "missing required field: body" else empty end),
            (if $record.created == null then "missing required field: created" else empty end),
            (if ($record.type != null and ($valid_types | index($record.type)) == null) then "invalid type \($record.type) (valid: \($valid_types | join(", ")) )" else empty end),
            (if ($record.scope != null and ($valid_scopes | index($record.scope)) == null) then "invalid scope \($record.scope) (valid: \($valid_scopes | join(", ")) )" else empty end),
            (if ($record.title | string_or_null | not) then "title must be null or string" else empty end),
            (if ($record.tags | type != "array") then "tags must be an array" else empty end),
            (if ($record.tags | type == "array" and (all(.[]?; type == "string" and ascii_downcase == .) | not)) then "tags must be lowercase strings" else empty end),
            (if ($record.authority == null or ($valid_authorities | index($record.authority)) == null) then "invalid authority \($record.authority) (valid: \($valid_authorities | join(", ")) )" else empty end),
            (if ($record.status == null or ($valid_statuses | index($record.status)) == null) then "invalid status \($record.status) (valid: \($valid_statuses | join(", ")) )" else empty end),
            (if ($record.provenance == null or ($valid_provenances | index($record.provenance)) == null) then "invalid provenance \($record.provenance) (valid: \($valid_provenances | join(", ")) )" else empty end),
            (if ($record.origin_session | string_or_null | not) then "origin_session must be null or string" else empty end),
            (if ($record.created | iso8601_or_null | not) then "created must be an ISO-8601 timestamp" else empty end),
            (if ($record.verified_at | iso8601_or_null | not) then "verified_at must be null or ISO-8601 timestamp" else empty end),
            (if (($record.authority == "verified" or $record.authority == "published") and $record.verified_at == null) then "verified_at is required when authority=\($record.authority)" else empty end),
            (if ($record.authority == "candidate" and $record.verified_at != null) then "verified_at must be null when authority=candidate" else empty end),
            (if ($record.review_due | iso8601_or_null | not) then "review_due must be null or ISO-8601 timestamp" else empty end),
            (if ($record.superseded_by | string_or_null | not) then "superseded_by must be null or string" else empty end),
            (if ($record.status == "superseded" and ($record.superseded_by == null or $record.superseded_by == "")) then "superseded_by is required when status=superseded" else empty end),
            (if ($record.status != "superseded" and $record.superseded_by != null) then "superseded_by must be null unless status=superseded" else empty end),
            (if ($record.contradicts | array_of_strings | not) then "contradicts must be an array of strings" else empty end),
            (if ($record.metadata | type != "object") then "metadata must be an object" else empty end),
            (if ($record.metadata | type == "object" and (($metadata_keys - ($record.metadata | keys_unsorted)) | length > 0)) then "metadata missing keys: \(($metadata_keys - ($record.metadata | keys_unsorted)) | join(", "))" else empty end),
            (if ($record.metadata | type == "object" and ((($record.metadata | keys_unsorted) - $metadata_keys) | length > 0)) then "metadata has invalid keys: \((($record.metadata | keys_unsorted) - $metadata_keys) | join(", "))" else empty end),
            (if ($record.metadata | type == "object" and ($record.metadata.published_artifacts | type != "array")) then "metadata.published_artifacts must be an array" else empty end),
            (if ($record.metadata | type == "object" and ($record.metadata.owner | string_or_null | not)) then "metadata.owner must be null or string" else empty end),
            (if ($record.metadata | type == "object" and ($record.metadata.sensitivity | string_or_null | not)) then "metadata.sensitivity must be null or string" else empty end),
            (if ($record.metadata | type == "object" and ($record.metadata.validation_method | string_or_null | not)) then "metadata.validation_method must be null or string" else empty end),
            (if ($record.metadata | type == "object" and ($record.metadata.last_verified | iso8601_or_null | not)) then "metadata.last_verified must be null or ISO-8601 timestamp" else empty end),
            (if ($record.metadata | type == "object" and ($record.metadata.freshness_days | number_or_null | not)) then "metadata.freshness_days must be null or number" else empty end),
            (if ($record.metadata | type == "object" and ($record.metadata.legacy_manifest_id | string_or_null | not)) then "metadata.legacy_manifest_id must be null or string" else empty end),
            (if ($record.metadata | type == "object" and ($record.metadata.legacy_manifest_path | string_or_null | not)) then "metadata.legacy_manifest_path must be null or string" else empty end),
            (if ($record.metadata | type == "object" and ($record.metadata.legacy_authority | string_or_null | not)) then "metadata.legacy_authority must be null or string" else empty end),
            (if ($record.metadata | type == "object" and ($record.metadata.source_kind | string_or_null | not)) then "metadata.source_kind must be null or string" else empty end),
            (if ($record.source | string_or_null | not) then "source must be null or string" else empty end),
            (if ($record.quality_score | number_or_null | not) then "quality_score must be null or number" else empty end)
        ]
        | map(select(length > 0))
        | .[]
    ')

    if [[ -n "$errors" ]]; then
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            echo "Error: $line" >&2
        done <<< "$errors"
        return 1
    fi

    warning=$(printf '%s' "$json_string" | jq -r --arg now "$now_iso" '
        if .review_due == null or .status == "stale" or .status == "superseded" or .status == "retracted" then empty
        elif try ((.review_due | fromdateiso8601) < ($now | fromdateiso8601)) catch false then
            "review_due is in the past but status is not stale"
        else empty end
    ')
    if [[ -n "$warning" ]]; then
        wisdom_log WARN "$warning"
    fi

    return 0
}

# --------------------------------------------------------------------------
# 25. wisdom_authority_rank — Convert authority string to numeric rank
#     Args: $1=authority_string
#     Outputs: numeric rank: published=3, verified=2, candidate=1, unknown=0
# --------------------------------------------------------------------------
wisdom_authority_rank() {
    local authority normalized_authority
    authority="$1"
    normalized_authority=$(wisdom_normalize_authority "$authority")

    case "$normalized_authority" in
        published) echo 3 ;;
        verified)  echo 2 ;;
        candidate) echo 1 ;;
        *)         echo 0 ;;
    esac
}

# --------------------------------------------------------------------------
# 26. wisdom_validate_jsonl_line — Validate a JSONL entry against schema
#     Args: $1=json_string
#     Returns: 0 if valid, 1 if invalid (errors on stderr)
# --------------------------------------------------------------------------
wisdom_validate_jsonl_line() {
    local json_string="$1"
    local normalized

    if ! printf '%s' "$json_string" | jq empty 2>/dev/null; then
        echo "Error: not valid JSON" >&2
        return 1
    fi

    normalized=$(wisdom_normalize_record "$json_string") || return 1
    wisdom_validate_canonical "$normalized"
}

# --------------------------------------------------------------------------
# 27. wisdom_atomic_append — Atomic append with flock-based file locking
#     Args: $1=file_path, $2=content
#     Returns: 0 on success, 1 on lock failure
# --------------------------------------------------------------------------
wisdom_atomic_append() {
    local file="$1"
    local content="$2"
    local lockfile="${file}.lock"
    
    # Check if flock is available
    if ! command -v flock >/dev/null 2>&1; then
        echo "WARNING: flock not available, falling back to non-atomic append" >&2
        echo "$content" >> "$file"
        return 0
    fi
    
    (
        flock -w 10 200 || { echo "ERROR: Could not acquire lock on $file" >&2; return 1; }
        echo "$content" >> "$file"
    ) 200>"$lockfile"
}

# --------------------------------------------------------------------------
# 28. wisdom_atomic_write — Atomic write with flock-based file locking
#     Args: $1=file_path, $2=content
#     Returns: 0 on success, 1 on lock failure
# --------------------------------------------------------------------------
wisdom_atomic_write() {
    local file="$1"
    local content="$2"
    local lockfile="${file}.lock"
    
    # Check if flock is available
    if ! command -v flock >/dev/null 2>&1; then
        echo "WARNING: flock not available, falling back to non-atomic write" >&2
        echo "$content" > "$file"
        return 0
    fi
    
    (
        flock -w 10 200 || { echo "ERROR: Could not acquire lock on $file" >&2; return 1; }
        echo "$content" > "$file"
    ) 200>"$lockfile"
}

# Backward-compatible alias for knowledge subsystem
knowledge_atomic_write() { wisdom_atomic_write "$@"; }
