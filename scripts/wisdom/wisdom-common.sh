# wisdom-common.sh — Shared library for wisdom subsystem
# Source guard
[[ -n "${_WISDOM_COMMON_LOADED:-}" ]] && return 0
_WISDOM_COMMON_LOADED=1

# Constants
WISDOM_ROOT="${HOME}/.sisyphus/wisdom"
WISDOM_SCRIPTS="${HOME}/.sisyphus/scripts"
WISDOM_VALID_TYPES=("gotcha" "pattern" "fact" "decision" "warning")
WISDOM_VALID_SCOPES=("system" "project" "plan")

# Global error flag for wisdom_log ERROR
_WISDOM_ERROR=0

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

    # Atomic write: cat existing + new line -> tmp, then mv
    local tmp
    tmp=$(mktemp "${store_path}.tmp.XXXXXX") || { echo "Error: mktemp failed" >&2; return 2; }

    if ! { cat "$store_path" 2>/dev/null; printf '%s\n' "$json_line"; } > "$tmp"; then
        rm -f "$tmp"
        echo "Error: write to temp file failed" >&2
        return 2
    fi

    if ! mv -f "$tmp" "$store_path"; then
        rm -f "$tmp"
        echo "Error: mv to store failed" >&2
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
# 8. wisdom_validate_jsonl_line — Validate a JSONL entry against schema
#    Args: $1=json_string
#    Returns: 0 if valid, 1 if invalid (errors on stderr)
# --------------------------------------------------------------------------
wisdom_validate_jsonl_line() {
    local json_string="$1"

    # Check valid JSON
    if ! printf '%s' "$json_string" | jq empty 2>/dev/null; then
        echo "Error: not valid JSON" >&2
        return 1
    fi

    # Check required fields exist
    local missing
    missing=$(printf '%s' "$json_string" | jq -r '
        [
            (if .id          == null then "id"      else empty end),
            (if .type        == null then "type"    else empty end),
            (if .scope       == null then "scope"   else empty end),
            (if .body        == null then "body"    else empty end),
            (if .created     == null then "created" else empty end)
        ] | join(", ")
    ')
    if [[ -n "$missing" ]]; then
        echo "Error: missing required fields: $missing" >&2
        return 1
    fi

    # Validate type
    local entry_type
    entry_type=$(printf '%s' "$json_string" | jq -r '.type')
    local type_valid=false
    local t
    for t in "${WISDOM_VALID_TYPES[@]}"; do
        if [[ "$entry_type" == "$t" ]]; then
            type_valid=true
            break
        fi
    done
    if [[ "$type_valid" == false ]]; then
        echo "Error: invalid type '$entry_type' (valid: ${WISDOM_VALID_TYPES[*]})" >&2
        return 1
    fi

    # Validate scope
    local entry_scope
    entry_scope=$(printf '%s' "$json_string" | jq -r '.scope')
    local scope_valid=false
    local sv
    for sv in "${WISDOM_VALID_SCOPES[@]}"; do
        if [[ "$entry_scope" == "$sv" ]]; then
            scope_valid=true
            break
        fi
    done
    if [[ "$scope_valid" == false ]]; then
        echo "Error: invalid scope '$entry_scope' (valid: ${WISDOM_VALID_SCOPES[*]})" >&2
        return 1
    fi

    return 0
}

# --------------------------------------------------------------------------
# 9. wisdom_escape_json — Escape a string for safe JSON embedding
#    Args: $1=string
#    Outputs: JSON-escaped string WITH surrounding quotes
# --------------------------------------------------------------------------
wisdom_escape_json() {
    printf '%s' "$1" | jq -Rs .
}

# --------------------------------------------------------------------------
# 10. wisdom_classify_type — Keyword-based type classification
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
# 11. wisdom_check_secret — Detect secrets/credentials in content
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
# 12. wisdom_require_jq — Check that jq is available
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
# 13. wisdom_log — Log a message to stderr
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
