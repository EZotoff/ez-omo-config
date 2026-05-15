#!/usr/bin/env bash
set -euo pipefail

# knowledge-promote.sh — DEPRECATED compatibility shim.
# Delegates to wisdom-publish.sh. Preserves legacy CLI interface.

SCRIPT_DIR="$(dirname "$0")"

WISDOM_COMMON="${SCRIPT_DIR}/wisdom-common.sh"
if [[ ! -f "$WISDOM_COMMON" ]]; then
  WISDOM_COMMON="${SCRIPT_DIR}/wisdom/wisdom-common.sh"
fi

if [[ -f "$WISDOM_COMMON" ]]; then
  source "$WISDOM_COMMON"
  wisdom_init_observability "$(basename "$0")"
fi

# Find wisdom-publish.sh: same dir at runtime, or scripts/wisdom/ in repo
WISDOM_PUBLISH="${SCRIPT_DIR}/wisdom-publish.sh"
if [[ ! -f "$WISDOM_PUBLISH" ]]; then
  WISDOM_PUBLISH="${SCRIPT_DIR}/wisdom/wisdom-publish.sh"
fi

_KNOWLEDGE_PROMOTE_START_MS=$(date +%s%3N 2>/dev/null || echo "")
_KNOWLEDGE_PROMOTE_WISDOM_ID=""
_KNOWLEDGE_PROMOTE_TYPE=""
_KNOWLEDGE_PROMOTE_SCOPE=""
_KNOWLEDGE_PROMOTE_REASON_HASH=""
_KNOWLEDGE_PROMOTE_REASON_PREVIEW=""

_knowledge_promote_emit_event() {
  local rc=$?
  command -v wisdom_emit_event >/dev/null 2>&1 || return 0

  local status="ok"
  [[ "$rc" -ne 0 ]] && status="error"

  local duration_ms_json="null"
  if [[ -n "${_KNOWLEDGE_PROMOTE_START_MS:-}" ]]; then
    local now_ms
    now_ms=$(date +%s%3N 2>/dev/null || echo "")
    if [[ -n "$now_ms" ]]; then
      duration_ms_json=$((now_ms - _KNOWLEDGE_PROMOTE_START_MS))
    fi
  fi

  local payload='{}'
  payload=$(jq -nc \
    --arg record_id "${_KNOWLEDGE_PROMOTE_WISDOM_ID:-}" \
    --arg manifest_type "${_KNOWLEDGE_PROMOTE_TYPE:-}" \
    --arg scope "${_KNOWLEDGE_PROMOTE_SCOPE:-}" \
    --arg reason_hash "${_KNOWLEDGE_PROMOTE_REASON_HASH:-}" \
    --arg reason_preview "${_KNOWLEDGE_PROMOTE_REASON_PREVIEW:-}" \
    --argjson duration_ms "$duration_ms_json" \
    '{
      record_id: (if $record_id == "" then null else $record_id end),
      manifest_type: (if $manifest_type == "" then null else $manifest_type end),
      scope: (if $scope == "" then null else $scope end),
      reason_hash: (if $reason_hash == "" then null else $reason_hash end),
      reason_preview: (if $reason_preview == "" then null else $reason_preview end),
      duration_ms: $duration_ms
    }' 2>/dev/null) || payload='{}'

  wisdom_emit_event "wisdom.promote.knowledge" "$status" "$payload"
}

trap _knowledge_promote_emit_event EXIT

{
  echo "WARNING: knowledge-promote.sh is deprecated. Use wisdom-publish.sh instead." >&2
  echo "  wisdom-publish.sh --id <wisdom-id> [--type TYPE] [--reason TEXT] [--emit-manifest]" >&2
} >&2

usage() {
  cat >&2 <<'EOF'
Usage: knowledge-promote.sh --wisdom-id ID --type TYPE --reason "WHY" [--scope SCOPE]

DEPRECATED: This script is a compatibility shim for wisdom-publish.sh.
Please migrate to: wisdom-publish.sh --id ID --type TYPE --reason TEXT --emit-manifest

Required:
  --wisdom-id ID       Wisdom entry ID to promote
  --type TYPE          Manifest type
  --reason TEXT        Why promoting (audit trail)

Optional:
  --scope SCOPE        Override manifest scope (system|workspace|project)
EOF
  exit 2
}

WISDOM_ID=""
MANIFEST_TYPE=""
REASON=""
SCOPE_OVERRIDE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --wisdom-id) WISDOM_ID="$2"; shift 2 ;;
    --type)      MANIFEST_TYPE="$2"; shift 2 ;;
    --reason)    REASON="$2"; shift 2 ;;
    --scope)     SCOPE_OVERRIDE="$2"; shift 2 ;;
    --help|-h)   usage ;;
    *)           echo "Unknown flag: $1" >&2; usage ;;
  esac
done

[[ -z "$WISDOM_ID" ]] && { echo "ERROR: --wisdom-id required" >&2; exit 2; }
[[ -z "$MANIFEST_TYPE" ]] && { echo "ERROR: --type required" >&2; exit 2; }
[[ -z "$REASON" ]] && { echo "ERROR: --reason required" >&2; exit 2; }

_KNOWLEDGE_PROMOTE_WISDOM_ID="$WISDOM_ID"
_KNOWLEDGE_PROMOTE_TYPE="$MANIFEST_TYPE"
_KNOWLEDGE_PROMOTE_SCOPE="$SCOPE_OVERRIDE"
if command -v hash_text_sha256 >/dev/null 2>&1; then
  _KNOWLEDGE_PROMOTE_REASON_HASH=$(hash_text_sha256 "$REASON")
elif command -v sha256sum >/dev/null 2>&1; then
  _KNOWLEDGE_PROMOTE_REASON_HASH=$(printf '%s' "$REASON" | sha256sum | awk '{print $1}')
elif command -v shasum >/dev/null 2>&1; then
  _KNOWLEDGE_PROMOTE_REASON_HASH=$(printf '%s' "$REASON" | shasum -a 256 | awk '{print $1}')
fi
if command -v wisdom_redact_preview >/dev/null 2>&1; then
  _KNOWLEDGE_PROMOTE_REASON_PREVIEW=$(wisdom_redact_preview "$REASON")
else
  _KNOWLEDGE_PROMOTE_REASON_PREVIEW="$REASON"
fi

WP_ARGS=("--id" "$WISDOM_ID" "--type" "$MANIFEST_TYPE" "--reason" "$REASON" "--emit-manifest")
[[ -n "$SCOPE_OVERRIDE" ]] && WP_ARGS+=("--manifest-scope" "$SCOPE_OVERRIDE")

"$WISDOM_PUBLISH" "${WP_ARGS[@]}"
exit $?
