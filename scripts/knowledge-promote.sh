#!/usr/bin/env bash
set -euo pipefail

# knowledge-promote.sh — DEPRECATED compatibility shim.
# Delegates to wisdom-publish.sh. Preserves legacy CLI interface.

SCRIPT_DIR="$(dirname "$0")"

# Find wisdom-common.sh
WISDOM_COMMON="${SCRIPT_DIR}/wisdom-common.sh"
if [[ ! -f "$WISDOM_COMMON" ]]; then
  WISDOM_COMMON="${SCRIPT_DIR}/wisdom/wisdom-common.sh"
fi
source "$WISDOM_COMMON" 2>/dev/null || { echo "ERROR: Failed to source wisdom-common.sh" >&2; exit 1; }
wisdom_init_observability "$(basename "$0")"

# Find wisdom-publish.sh: same dir at runtime, or scripts/wisdom/ in repo
WISDOM_PUBLISH="${SCRIPT_DIR}/wisdom-publish.sh"
if [[ ! -f "$WISDOM_PUBLISH" ]]; then
  WISDOM_PUBLISH="${SCRIPT_DIR}/wisdom/wisdom-publish.sh"
fi

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

WP_ARGS=("--id" "$WISDOM_ID" "--type" "$MANIFEST_TYPE" "--reason" "$REASON" "--emit-manifest")
[[ -n "$SCOPE_OVERRIDE" ]] && WP_ARGS+=("--manifest-scope" "$SCOPE_OVERRIDE")

# Emit shim event before delegating; child inherits trace via WISDOM_TRACE_ID
reason_preview=$(wisdom_redact_preview "$REASON")
emit_payload=$(jq -nc \
  --arg wisdom_id "$WISDOM_ID" \
  --arg manifest_type "$MANIFEST_TYPE" \
  --arg reason_preview "$reason_preview" \
  --arg scope_override "${SCOPE_OVERRIDE:-}" \
  '{
    wisdom_id: $wisdom_id,
    manifest_type: $manifest_type,
    reason_preview: $reason_preview,
    scope_override: (if $scope_override == "" then null else $scope_override end)
  }' 2>/dev/null) || emit_payload='{}'
wisdom_emit_event "wisdom.promote.knowledge" "success" "$emit_payload"

"$WISDOM_PUBLISH" "${WP_ARGS[@]}"
exit $?
