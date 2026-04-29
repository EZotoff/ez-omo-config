#!/usr/bin/env bash
set -euo pipefail

# knowledge-promote.sh — DEPRECATED compatibility shim.
# Delegates to wisdom-publish.sh. Preserves legacy CLI interface.

SCRIPT_DIR="$(dirname "$0")"

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

"$WISDOM_PUBLISH" "${WP_ARGS[@]}"
exit $?
