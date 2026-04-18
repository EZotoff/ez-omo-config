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

# Knowledge Capture Extension Fields (optional, additive)
# authority: Source authority level - "wisdom" (default, agent observation), "manifest" (promoted from manifest), "verified" (human-verified)
# provenance: How this entry was created - "closeout" (closeout gate), "nomination" (hook-nominated), "promotion" (promoted from manifest), "manual" (direct write)
# origin_session: OpenCode session ID where this was captured
# verified_at: ISO-8601 timestamp of last verification (null if unverified)
# review_due: ISO-8601 timestamp for scheduled review (null if none)
# superseded_by: ID of the entry that replaces this one (null if active)

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

# --------------------------------------------------------------------------
# 14. wisdom_field_with_default — Extract field from JSONL with default
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
# 15. wisdom_authority_rank — Convert authority string to numeric rank
#     Args: $1=authority_string
#     Outputs: numeric rank: manifest=3, verified=2, wisdom=1, unknown=0
# --------------------------------------------------------------------------
wisdom_authority_rank() {
  local authority="$1"
  case "$authority" in
    manifest)  echo 3 ;;
    verified)  echo 2 ;;
    wisdom)    echo 1 ;;
    *)         echo 0 ;;
  esac
}

# --------------------------------------------------------------------------
# 16. wisdom_atomic_append — Atomic append with flock-based file locking
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
# 17. knowledge_atomic_write — Atomic write with flock-based file locking
#     Args: $1=file_path, $2=content
#     Returns: 0 on success, 1 on lock failure
# --------------------------------------------------------------------------
knowledge_atomic_write() {
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
