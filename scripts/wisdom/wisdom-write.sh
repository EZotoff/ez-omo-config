#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/wisdom-common.sh"
wisdom_require_jq

SCOPE="system"
TYPE=""
TAGS=""
CONTENT=""
SOURCE=""
PROJECT_ID=""
SCORE=0

usage() {
    cat >&2 <<'EOF'
Usage: wisdom-write.sh [OPTIONS]
  --scope       system|project|plan       (default: system)
  --type        gotcha|pattern|fact|decision|warning (auto-classified if omitted)
  --tags        comma-separated tags      (required)
  --content     "content string"          (reads stdin if omitted)
  --source      source identifier         (optional)
  --project-id  project/plan identifier   (required for project/plan scope)
  --score       quality score integer     (default: 0)
EOF
    exit 2
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --scope)      SCOPE="$2";      shift 2 ;;
        --type)       TYPE="$2";       shift 2 ;;
        --tags)       TAGS="$2";       shift 2 ;;
        --content)    CONTENT="$2";    shift 2 ;;
        --source)     SOURCE="$2";     shift 2 ;;
        --project-id) PROJECT_ID="$2"; shift 2 ;;
        --score)      SCORE="$2";      shift 2 ;;
        *)
            wisdom_log ERROR "Unknown option: $1"
            usage
            ;;
    esac
done

if [[ -z "$CONTENT" ]]; then
    CONTENT=$(cat)
fi

if [[ -z "$TAGS" ]]; then
    wisdom_log ERROR "--tags is required"
    exit 2
fi

if [[ -z "$CONTENT" || -z "${CONTENT// /}" ]]; then
    wisdom_log ERROR "Content must not be empty or whitespace-only"
    exit 2
fi

if [[ "${#CONTENT}" -lt 20 ]]; then
    wisdom_log ERROR "Content too short (${#CONTENT} chars, minimum 20)"
    exit 2
fi

if [[ "$SCOPE" == "project" || "$SCOPE" == "plan" ]] && [[ -z "$PROJECT_ID" ]]; then
    wisdom_log ERROR "--project-id is required when scope=$SCOPE"
    exit 2
fi

if ! wisdom_check_secret "$CONTENT"; then
    wisdom_log ERROR "Entry blocked: secret detected in content"
    exit 3
fi

if [[ -z "$TYPE" ]]; then
    TYPE=$(wisdom_classify_type "$CONTENT")
    wisdom_log INFO "Auto-classified type: $TYPE"
fi

store_path=$(wisdom_get_store_path "$SCOPE" "$PROJECT_ID") || exit 1
wisdom_init_store "$store_path"

id=$(wisdom_generate_id)
created=$(date -u +%Y-%m-%dT%H:%M:%SZ)

tags_json=$(printf '%s' "$TAGS" | jq -R 'split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0))')

entry=$(jq -nc \
    --arg id "$id" \
    --arg type "$TYPE" \
    --arg scope "$SCOPE" \
    --argjson tags "$tags_json" \
    --arg body "$CONTENT" \
    --arg created "$created" \
    --arg source "$SOURCE" \
    --argjson score "$SCORE" \
    '{
        id: $id,
        type: $type,
        scope: $scope,
        tags: $tags,
        body: $body,
        created: $created,
        accessed: 0,
        last_accessed: "",
        source: $source,
        quality_score: $score
    }')

if ! wisdom_validate_jsonl_line "$entry"; then
    wisdom_log ERROR "Generated entry failed validation"
    exit 3
fi

if ! wisdom_append_entry "$entry" "$store_path"; then
    wisdom_log ERROR "Failed to write entry to store"
    exit 3
fi

if ! wisdom_read_entry "$id" "$store_path" >/dev/null 2>&1; then
    wisdom_log ERROR "Verification failed: entry not found after write"
    exit 3
fi

wisdom_log INFO "Entry written to $store_path"

printf '%s\n' "$id"
exit 0
