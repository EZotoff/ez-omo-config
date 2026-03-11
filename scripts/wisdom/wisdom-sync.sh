#!/usr/bin/env bash
# wisdom-sync.sh — Scan notepad learnings and sync new entries into wisdom JSONL stores
# Pipeline: scan → split → filter → dedup → classify → LLM gate → write → update state
set -euo pipefail

source "$(dirname "$0")/wisdom-common.sh"

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
NOTEPADS_ROOT="${HOME}/.sisyphus/notepads"
SYNC_STATE_FILE="${WISDOM_ROOT}/.sync-state"
SYNC_LOG_FILE="${WISDOM_ROOT}/.sync-log"
WRITE_SCRIPT="$(dirname "$0")/wisdom-write.sh"

LOG_ROTATE_LINES=500
MIN_BODY_LENGTH=20

# ---------------------------------------------------------------------------
# Flags (set by CLI parsing)
# ---------------------------------------------------------------------------
DRY_RUN=false
SKIP_LLM=false
VERBOSE=false

# ---------------------------------------------------------------------------
# Counters
# ---------------------------------------------------------------------------
SYNCED_COUNT=0
SKIPPED_COUNT=0
REJECTED_COUNT=0
ERROR_COUNT=0

# ---------------------------------------------------------------------------
# usage — Print help text
# ---------------------------------------------------------------------------
usage() {
    cat >&2 <<'EOF'
Usage: wisdom-sync.sh [OPTIONS]

Scan notepad learnings files and sync new entries into the wisdom store.

Options:
  --dry-run    Show what would be synced without making changes
  --skip-llm   Skip LLM quality gate (accept all entries scoring >= min body)
  --verbose    Print extra detail about each pipeline stage
  --help       Show this help message

Exit codes:
  0  Success (one or more entries synced)
  1  No new entries found
  2  Error during processing

Pipeline stages:
  1. Scan     Find all ~/.sisyphus/notepads/*/learnings.md files
  2. Split    Split each file into sections on ## or ### headers
  3. Filter   Skip sections with body < 20 characters
  4. Dedup    SHA-256 hash check against .sync-state
  5. Classify Auto-determine type via wisdom_classify_type
  6. LLM Gate Score 0-5 via opencode chat (unless --skip-llm)
  7. Write    Call wisdom-write.sh for accepted entries
  8. State    Append hashes to .sync-state
EOF
    exit 0
}

# ---------------------------------------------------------------------------
# log — Log a timestamped message to stderr AND .sync-log
# Args: $1=message
# ---------------------------------------------------------------------------
log() {
    local msg
    msg="[$(date +%Y-%m-%dT%H:%M:%S%z)] $1"
    printf '%s\n' "$msg" >&2
    printf '%s\n' "$msg" >> "$SYNC_LOG_FILE"
}

# ---------------------------------------------------------------------------
# vlog — Verbose-only logging
# Args: $1=message
# ---------------------------------------------------------------------------
vlog() {
    if [[ "$VERBOSE" == true ]]; then
        log "VERBOSE: $1"
    fi
}

# ---------------------------------------------------------------------------
# rotate_log — Rotate .sync-log if it exceeds LOG_ROTATE_LINES
# ---------------------------------------------------------------------------
rotate_log() {
    if [[ ! -f "$SYNC_LOG_FILE" ]]; then
        return
    fi
    local line_count
    line_count=$(wc -l < "$SYNC_LOG_FILE")
    if (( line_count > LOG_ROTATE_LINES )); then
        mv -f "$SYNC_LOG_FILE" "${SYNC_LOG_FILE}.1"
        touch "$SYNC_LOG_FILE"
        vlog "Rotated sync log (was ${line_count} lines)"
    fi
}

# ---------------------------------------------------------------------------
# hash_body — SHA-256 hash of body text
# Args: $1=body
# Outputs: hex hash on stdout
# ---------------------------------------------------------------------------
hash_body() {
    printf '%s' "$1" | sha256sum | cut -d' ' -f1
}

# ---------------------------------------------------------------------------
# is_already_synced — Check if hash exists in .sync-state
# Args: $1=hash
# Returns: 0 if already synced, 1 if new
# ---------------------------------------------------------------------------
is_already_synced() {
    local hash="$1"
    if [[ -f "$SYNC_STATE_FILE" ]] && grep -qF "$hash" "$SYNC_STATE_FILE"; then
        return 0
    fi
    return 1
}

# ---------------------------------------------------------------------------
# extract_tags — Derive tags from notepad dir name and section header
# Args: $1=notepad_dir_name, $2=header_line
# Outputs: comma-separated tags string
# ---------------------------------------------------------------------------
extract_tags() {
    local notepad_name="$1"
    local header="$2"

    # Start with sync source and notepad name
    local tags="sync,${notepad_name}"

    # Extract meaningful words from header (strip ## prefix, date, "Task Tn:" prefix)
    local cleaned_header
    cleaned_header=$(printf '%s' "$header" | sed -E 's/^#{2,3}\s+//; s/\[?[0-9]{4}-[0-9]{2}-[0-9]{2}\]?\s*//; s/Task\s+[A-Za-z0-9]+:\s*//')

    # Take lowercase words >= 3 chars, skip common stop words
    local word
    for word in $cleaned_header; do
        word="${word,,}"
        word="${word//[^a-z0-9-]/}"
        if [[ ${#word} -ge 3 ]] && \
           [[ "$word" != "the" && "$word" != "and" && "$word" != "for" && \
              "$word" != "with" && "$word" != "from" && "$word" != "that" && \
              "$word" != "this" && "$word" != "into" && "$word" != "has" && \
              "$word" != "was" && "$word" != "are" && "$word" != "not" ]]; then
            tags="${tags},${word}"
        fi
    done

    printf '%s' "$tags"
}

# ---------------------------------------------------------------------------
# llm_score — Call opencode chat to score entry quality 0-5
# Args: $1=body
# Outputs: integer score on stdout
# ---------------------------------------------------------------------------
llm_score() {
    local body="$1"
    local score

     score=$(printf 'Rate this wisdom entry quality 0-10 (0=useless, 10=critical). Reply with ONLY a single number, nothing else:\n\n%s' "$body" \
         | opencode chat 2>/dev/null \
         | grep -oP '^[0-9]+$' \
         | head -1) || true

    # Default to 3 if LLM fails or returns nothing
    if [[ -z "${score:-}" ]]; then
        score=3
    fi

    printf '%s' "$score"
}

# ---------------------------------------------------------------------------
# process_section — Run pipeline stages 3-7 on a single section
# Args: $1=header, $2=body, $3=notepad_dir_name, $4=notepad_path
# ---------------------------------------------------------------------------
process_section() {
    local header="$1"
    local body="$2"
    local notepad_name="$3"
    local notepad_path="$4"

    # --- Stage 3: Filter short bodies ---
    local body_length=${#body}
    if (( body_length < MIN_BODY_LENGTH )); then
        vlog "FILTER: Skipped (body ${body_length} chars < ${MIN_BODY_LENGTH}): ${header:0:60}"
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        return
    fi

    # --- Stage 4: Dedup via SHA-256 ---
    local hash
    hash=$(hash_body "$body")

    if is_already_synced "$hash"; then
        vlog "DEDUP: Already synced (hash=${hash:0:12}…): ${header:0:60}"
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        return
    fi

    # --- Stage 5: Classify type ---
    local entry_type
    entry_type=$(wisdom_classify_type "$body")
    vlog "CLASSIFY: type=${entry_type} for: ${header:0:60}"

    # --- Stage 5.5: Secret check ---
    if ! wisdom_check_secret "$body"; then
        log "BLOCKED: Secret detected in section: ${header:0:60}"
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        return
    fi

    # --- Stage 6: LLM Quality Gate ---
    local score=3
    if [[ "$SKIP_LLM" != true ]]; then
        score=$(llm_score "$body")
        vlog "LLM_SCORE: ${score} for: ${header:0:60}"
        if (( score < 3 )); then
            log "REJECTED: LLM score=${score} < 3 for: ${header:0:60}"
            REJECTED_COUNT=$((REJECTED_COUNT + 1))
            return
        fi
    fi

    # --- Stage 7: Write entry ---
    local tags
    tags=$(extract_tags "$notepad_name" "$header")

    if [[ "$DRY_RUN" == true ]]; then
        log "DRY-RUN: Would sync [type=${entry_type}, score=${score}, tags=${tags}]: ${header:0:80}"
        SYNCED_COUNT=$((SYNCED_COUNT + 1))
        return
    fi

     local write_output
     local write_rc=0
     write_output=$(printf '%s' "$body" | "$WRITE_SCRIPT" \
         --scope system \
         --type "$entry_type" \
         --tags "$tags" \
         --source "sync:${notepad_path}" \
         --score "$score" 2>&1) || write_rc=$?

    if (( write_rc == 0 )); then
        # --- Stage 8: Update state ---
        printf '%s\n' "$hash" >> "$SYNC_STATE_FILE"
        SYNCED_COUNT=$((SYNCED_COUNT + 1))
        log "SYNCED: [type=${entry_type}, score=${score}] ${header:0:80}"
    else
        ERROR_COUNT=$((ERROR_COUNT + 1))
        local err_msg
        err_msg=$(printf '%s' "$write_output" | tr '\n' ' ')
        log "ERROR: Write failed for ${header:0:60}: ${err_msg}"
    fi
}

# ---------------------------------------------------------------------------
# split_and_process — Split a learnings file into sections and process each
# Args: $1=file_path
# ---------------------------------------------------------------------------
split_and_process() {
    local file_path="$1"
    local notepad_name
    notepad_name=$(basename "$(dirname "$file_path")")

    vlog "SCAN: Processing ${file_path}"

    local current_header=""
    local current_body=""
    local in_section=false
    local line

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^#{2,3}[[:space:]]+ ]]; then
            # New header encountered — flush previous section
            if [[ "$in_section" == true && -n "$current_header" ]]; then
                # Trim leading/trailing whitespace from body
                local trimmed_body
                trimmed_body=$(printf '%s' "$current_body" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
                process_section "$current_header" "$trimmed_body" "$notepad_name" "$file_path"
            fi
            current_header="$line"
            current_body=""
            in_section=true
        elif [[ "$in_section" == true ]]; then
            if [[ -n "$current_body" ]]; then
                current_body+=$'\n'"$line"
            else
                current_body="$line"
            fi
        fi
    done < "$file_path"

    # Flush final section
    if [[ "$in_section" == true && -n "$current_header" ]]; then
        local trimmed_body
        trimmed_body=$(printf '%s' "$current_body" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        process_section "$current_header" "$trimmed_body" "$notepad_name" "$file_path"
    fi
}

# ---------------------------------------------------------------------------
# main — Entry point
# ---------------------------------------------------------------------------
main() {
    # Parse CLI args
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)   DRY_RUN=true;  shift ;;
            --skip-llm)  SKIP_LLM=true; shift ;;
            --verbose)   VERBOSE=true;   shift ;;
            --help)      usage ;;
            *)
                wisdom_log ERROR "Unknown option: $1"
                usage
                ;;
        esac
    done

    # Ensure prerequisites
    wisdom_require_jq

    # Ensure directories and state files exist
    mkdir -p "$WISDOM_ROOT"
    touch "$SYNC_STATE_FILE"
    touch "$SYNC_LOG_FILE"

    # Rotate log if needed
    rotate_log

    log "=== SYNC RUN START (dry_run=${DRY_RUN}, skip_llm=${SKIP_LLM}, verbose=${VERBOSE}) ==="

    # Verify wisdom-write.sh is executable
    if [[ ! -x "$WRITE_SCRIPT" ]]; then
        log "ERROR: wisdom-write.sh not found or not executable at ${WRITE_SCRIPT}"
        exit 2
    fi

    # --- Stage 1: Scan for learnings files ---
    if [[ ! -d "$NOTEPADS_ROOT" ]]; then
        log "No notepads directory found at ${NOTEPADS_ROOT}"
        log "=== SYNC RUN END: synced=0 skipped=0 rejected=0 errors=0 ==="
        exit 1
    fi

    shopt -s nullglob
    local learning_files=("${NOTEPADS_ROOT}"/*/learnings.md)
    shopt -u nullglob

    if [[ ${#learning_files[@]} -eq 0 ]]; then
        log "No learnings.md files found"
        log "=== SYNC RUN END: synced=0 skipped=0 rejected=0 errors=0 ==="
        exit 1
    fi

    vlog "SCAN: Found ${#learning_files[@]} learnings file(s)"

    # --- Stage 2: Split and process each file ---
    local file
    for file in "${learning_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            continue
        fi
        split_and_process "$file"
    done

    # Summary
    log "=== SYNC RUN END: synced=${SYNCED_COUNT} skipped=${SKIPPED_COUNT} rejected=${REJECTED_COUNT} errors=${ERROR_COUNT} ==="

    if (( ERROR_COUNT > 0 )); then
        exit 2
    fi

    if (( SYNCED_COUNT == 0 )); then
        exit 1
    fi

    exit 0
}

# Only run main if executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
