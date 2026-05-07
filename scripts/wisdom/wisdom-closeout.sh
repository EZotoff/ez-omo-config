#!/usr/bin/env bash
set -euo pipefail

# wisdom-closeout.sh — Wisdom-native closeout capture handler
#
# Preserves closeout capture behavior while routing writes through canonical
# wisdom-write.sh and lifecycle updates through wisdom-edit.sh.

source "$(dirname "$0")/wisdom-common.sh"
wisdom_init_observability "$(basename "$0")"
wisdom_require_jq

WRITE_SCRIPT="$(dirname "$0")/wisdom-write.sh"
EDIT_SCRIPT="$(dirname "$0")/wisdom-edit.sh"

SCOPE="system"
TYPE=""
TAGS=""
CONTENT=""
PROJECT_ID=""
SESSION_ID=""
SOURCE="closeout:runtime"

usage() {
    cat >&2 <<'EOF'
Usage: wisdom-closeout.sh [OPTIONS]
  --content         "content string"           (reads stdin if omitted)
  --tags            comma-separated tags        (optional)
  --scope           system|project|plan         (default: system)
  --type            gotcha|pattern|fact|decision|warning (auto if omitted)
  --project-id      project/plan identifier     (required for project/plan)
  --session-id      source session id           (optional)
  --origin-session  alias of --session-id       (optional)
  --source          source identifier           (default: closeout:runtime)

Behavior:
  - Writes canonical Wisdom with provenance=closeout
  - If a clear replacement is detected, supersedes the previous record
  - If unresolved conflict is detected, annotates new record with contradicts

Exit codes:
  0  closeout written successfully
  2  bad arguments
  3  secret-like payload blocked
  4  lifecycle update failed after write
EOF
    exit 2
}

_emit_closeout_event() {
    local status="$1"
    local lifecycle_decision="${2:-}"
    local match_score="${3:-}"
    local record_id="${4:-}"
    local matched_id="${5:-}"
    local origin_session="${6:-}"

    local payload
    payload=$(jq -n \
        --arg lifecycle_decision "$lifecycle_decision" \
        --arg match_score "$match_score" \
        --arg record_id "$record_id" \
        --arg matched_id "$matched_id" \
        --arg origin_session "$origin_session" \
        '{
            lifecycle_decision: (if $lifecycle_decision == "" then null else $lifecycle_decision end),
            match_score: (if $match_score == "" then null else ($match_score | tonumber) end),
            match_score_bucket: (if $match_score == "" then null elif ($match_score | tonumber) >= 0.70 then "high" elif ($match_score | tonumber) >= 0.30 then "medium" else "low" end),
            record_id: (if $record_id == "" then null else $record_id end),
            superseded_ids: (if $lifecycle_decision == "replace" and $matched_id != "" then [$matched_id] else [] end),
            contradicted_ids: (if $lifecycle_decision == "conflict" and $matched_id != "" then [$matched_id] else [] end),
            origin_session: (if $origin_session == "" then null else $origin_session end)
        }' 2>/dev/null) || payload="{}"

    wisdom_emit_event "wisdom.capture.closeout" "$status" "$payload"
}

closeout_secret_check() {
    local content="$1"
    local lower

    if ! wisdom_check_secret "$content"; then
        return 1
    fi

    lower="${content,,}"

    # AWS access key IDs
    if [[ "$content" =~ AKIA[0-9A-Z]{16} ]]; then
        echo "Secret detected: AWS access key pattern" >&2
        return 1
    fi

    # Generic PEM/key blocks
    if [[ "$content" =~ -----BEGIN[[:space:]][A-Z0-9[:space:]_-]+----- ]]; then
        echo "Secret detected: PEM/key block" >&2
        return 1
    fi

    # Short-form API key tokens that still look credential-like
    if [[ "$lower" =~ sk-[a-z0-9_-]{8,} ]]; then
        echo "Secret detected: sk-* token pattern" >&2
        return 1
    fi

    # Common key assignment patterns
    if [[ "$lower" =~ api[_-]?key[[:space:]]*[:=][[:space:]]*[^[:space:]]+ ]]; then
        echo "Secret detected: api_key assignment" >&2
        return 1
    fi

    return 0
}

get_match_summary() {
    local store_path="$1"
    local scope="$2"
    local type="$3"
    local body="$4"

    if [[ ! -f "$store_path" || ! -s "$store_path" ]]; then
        return 1
    fi

    jq -sc --arg scope "$scope" --arg type "$type" --arg body "$body" '
        def tokens($text):
            ($text // "")
            | ascii_downcase
            | gsub("[^a-z0-9]+"; " ")
            | split(" ")
            | map(select(length > 2))
            | unique;
        def jaccard($left; $right):
            (($left + $right) | unique) as $u
            | if ($u | length) == 0 then 0
              else ((($left | map(select($right | index(.)))) | length) / ($u | length))
              end;
        (tokens($body)) as $incoming
        | [
            .[]
            | select(.scope == $scope)
            | select(.type == $type)
            | select((.status // "active") != "superseded" and (.status // "active") != "retracted")
            | . as $candidate
            | {
                id: $candidate.id,
                score: jaccard($incoming; tokens($candidate.body)),
                created: ($candidate.created // "")
              }
          ]
        | map(select(.score >= 0.30))
        | sort_by(-.score, -(.created | fromdateiso8601? // 0), .id)
        | {
            best_id: (.[0].id // ""),
            best_score: (.[0].score // 0),
            second_score: (.[1].score // 0),
            candidate_count: length
          }
    ' "$store_path"
}

determine_lifecycle_action() {
    local summary_json="$1"

    if [[ -z "$summary_json" ]]; then
        printf 'new||0\n'
        return 0
    fi

    local best_id best_score second_score count
    best_id=$(printf '%s' "$summary_json" | jq -r '.best_id // ""')
    best_score=$(printf '%s' "$summary_json" | jq -r '.best_score // 0')
    second_score=$(printf '%s' "$summary_json" | jq -r '.second_score // 0')
    count=$(printf '%s' "$summary_json" | jq -r '.candidate_count // 0')

    if [[ "$count" -eq 0 || -z "$best_id" ]]; then
        printf 'new||0\n'
        return 0
    fi

    # Clear replacement: strong nearest match with no similarly-strong rival.
    if [[ "$(jq -nr --argjson best "$best_score" --argjson second "$second_score" '($best >= 0.70) and ($second < 0.60)')" == "true" ]]; then
        printf 'replace|%s|%s\n' "$best_id" "$best_score"
        return 0
    fi

    # Unresolved conflict: similar prior record exists but replacement is ambiguous.
    printf 'conflict|%s|%s\n' "$best_id" "$best_score"
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
    wisdom_log ERROR "Closeout content must not be empty"
    _emit_closeout_event "failed" "skipped" "" "" "" "$SESSION_ID"
    exit 2
fi

if ! closeout_secret_check "$CONTENT"; then
    wisdom_log ERROR "Closeout entry blocked: secret-like content detected"
    _emit_closeout_event "failed" "skipped" "" "" "" "$SESSION_ID"
    exit 3
fi

if [[ -z "$TYPE" ]]; then
    TYPE=$(wisdom_classify_type "$CONTENT")
fi

store_path=$(wisdom_get_store_path "$SCOPE" "$PROJECT_ID") || exit 2
wisdom_init_store "$store_path"

match_summary=$(get_match_summary "$store_path" "$SCOPE" "$TYPE" "$CONTENT" || true)
IFS='|' read -r action matched_id _score <<< "$(determine_lifecycle_action "$match_summary")"

write_args=(
    --scope "$SCOPE"
    --type "$TYPE"
    --tags "$TAGS"
    --content "$CONTENT"
    --authority candidate
    --status active
    --provenance closeout
    --source "$SOURCE"
)

if [[ -n "$PROJECT_ID" ]]; then
    write_args+=(--project-id "$PROJECT_ID")
fi

if [[ -n "$SESSION_ID" ]]; then
    write_args+=(--origin-session "$SESSION_ID")
fi

new_id=$("$WRITE_SCRIPT" "${write_args[@]}")

if [[ "$action" == "replace" && -n "$matched_id" ]]; then
    edit_args=("$matched_id" --scope "$SCOPE" --set-status superseded --set-superseded-by "$new_id")
    if [[ -n "$PROJECT_ID" ]]; then
        edit_args+=(--project-id "$PROJECT_ID")
    fi
    if ! "$EDIT_SCRIPT" "${edit_args[@]}" >/dev/null; then
        wisdom_log ERROR "Closeout write succeeded but supersession failed for $matched_id"
        _emit_closeout_event "failed" "replace" "$_score" "$new_id" "$matched_id" "$SESSION_ID"
        exit 4
    fi
fi

if [[ "$action" == "conflict" && -n "$matched_id" ]]; then
    edit_args=("$new_id" --scope "$SCOPE" --set-contradicts "$matched_id")
    if [[ -n "$PROJECT_ID" ]]; then
        edit_args+=(--project-id "$PROJECT_ID")
    fi
    if ! "$EDIT_SCRIPT" "${edit_args[@]}" >/dev/null; then
        wisdom_log ERROR "Closeout write succeeded but contradicts update failed for $new_id"
        _emit_closeout_event "failed" "conflict" "$_score" "$new_id" "$matched_id" "$SESSION_ID"
        exit 4
    fi
fi

_emit_closeout_event "success" "$action" "$_score" "$new_id" "$matched_id" "$SESSION_ID"

printf '%s\n' "$new_id"
exit 0
