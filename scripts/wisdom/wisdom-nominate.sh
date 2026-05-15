#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/wisdom-common.sh"
wisdom_init_observability "$(basename "$0")"
wisdom_require_jq

WRITE_SCRIPT="$(dirname "$0")/wisdom-write.sh"

SCOPE="system"
TYPE=""
TAGS=""
CONTENT=""
PROJECT_ID=""
SESSION_ID=""
SOURCE="nomination:passive"

usage() {
    cat >&2 <<'EOF'
Usage: wisdom-nominate.sh [OPTIONS]
  --content         "content string"          (reads stdin if omitted)
  --tags            comma-separated tags       (optional for system scope)
  --scope           system|project|plan        (default: system)
  --type            gotcha|pattern|fact|decision|warning (optional)
  --project-id      project/plan identifier    (required for project/plan)
  --session-id      source session id          (optional)
  --origin-session  alias of --session-id      (optional)
  --source          source identifier          (default: nomination:passive)

Infra-only nomination policy (v1):
  - Allowed if scope=system
  - OR allowed when tags contain at least one infra tag:
    infra, config, deployment, setup
EOF
    exit 2
}

_emit_nomination_event() {
    local status="$1"
    local reason="${2:-}"
    local payload
    payload=$(jq -n \
        --arg scope "$SCOPE" \
        --arg project_id "$PROJECT_ID" \
        --arg type "$TYPE" \
        --arg tags "$TAGS" \
        --arg reason "$reason" \
        --arg origin_session "$SESSION_ID" \
        '{
            scope: $scope,
            project_id: (if $project_id == "" then null else $project_id end),
            type: (if $type == "" then null else $type end),
            tags: (if $tags == "" then null else $tags end),
            reason: (if $reason == "" then null else $reason end),
            origin_session: (if $origin_session == "" then null else $origin_session end)
        }' 2>/dev/null) || payload="{}"
    wisdom_emit_event "wisdom.capture.nomination" "$status" "$payload"
}

has_infra_tag() {
    local tags_csv="$1"
    local tag=""

    IFS=',' read -r -a _tags <<< "$tags_csv"
    for tag in "${_tags[@]}"; do
        tag="${tag#${tag%%[![:space:]]*}}"
        tag="${tag%${tag##*[![:space:]]}}"
        tag="${tag,,}"
        case "$tag" in
            infra|config|deployment|setup)
                return 0
                ;;
        esac
    done

    return 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --content)        CONTENT="$2";    shift 2 ;;
        --tags)           TAGS="$2";       shift 2 ;;
        --scope)          SCOPE="$2";      shift 2 ;;
        --type)           TYPE="$2";       shift 2 ;;
        --project-id)     PROJECT_ID="$2"; shift 2 ;;
        --session-id|--origin-session)
                          SESSION_ID="$2"; shift 2 ;;
        --source)         SOURCE="$2";     shift 2 ;;
        --help|-h)        usage ;;
        *)
            wisdom_log ERROR "Unknown option: $1"
            usage
            ;;
    esac
done

if [[ -z "$CONTENT" ]]; then
    CONTENT=$(cat)
fi

if [[ -z "$CONTENT" || -z "${CONTENT// /}" ]]; then
    wisdom_log ERROR "Nomination content must not be empty"
    _emit_nomination_event "skipped" "empty content"
    exit 2
fi

# Validate scope/project combination using canonical resolver.
wisdom_get_store_path "$SCOPE" "$PROJECT_ID" >/dev/null

if [[ "$SCOPE" != "system" ]] && ! has_infra_tag "$TAGS"; then
    wisdom_log WARN "Nomination rejected: passive nomination is infra-only in v1"
    wisdom_log WARN "Allowed when scope=system OR tags include one of: infra, config, deployment, setup"
    wisdom_log WARN "Received scope='${SCOPE}', tags='${TAGS:-<none>}'"
    _emit_nomination_event "skipped" "infra-only policy v1"
    exit 4
fi

write_args=(
    --scope "$SCOPE"
    --tags "$TAGS"
    --content "$CONTENT"
    --authority candidate
    --status active
    --provenance nomination
)

if [[ -n "$TYPE" ]]; then
    write_args+=(--type "$TYPE")
fi

if [[ -n "$SOURCE" ]]; then
    write_args+=(--source "$SOURCE")
fi

if [[ -n "$PROJECT_ID" ]]; then
    write_args+=(--project-id "$PROJECT_ID")
fi

if [[ -n "$SESSION_ID" ]]; then
    write_args+=(--origin-session "$SESSION_ID")
fi

"$WRITE_SCRIPT" "${write_args[@]}"
_emit_nomination_event "success" ""
