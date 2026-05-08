#!/usr/bin/env bash
set -euo pipefail

# wisdom-publish.sh — Publish a Wisdom entry as a derivative artifact.
# Canonical record is updated (authority=published, verified_at=now) but NEVER superseded.
# Usage: wisdom-publish.sh --id ID [--scope SCOPE] [--project-id PID]
#                          [--type TYPE] [--reason TEXT]
#                          [--manifest-scope SCOPE] [--emit-manifest] [--dry-run]

SCRIPT_DIR="$(dirname "$0")"
source "${SCRIPT_DIR}/knowledge-constants.sh" 2>/dev/null || { echo "ERROR: Failed to source knowledge-constants.sh" >&2; exit 1; }
source "${SCRIPT_DIR}/wisdom-common.sh" || { echo "ERROR: Failed to source wisdom-common.sh" >&2; exit 1; }
wisdom_init_observability "$(basename "$0")"

hash_text_sha256() {
  local value="${1:-}"
  if [[ -z "$value" ]]; then
    printf ''
    return 0
  fi
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$value" | sha256sum | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    printf '%s' "$value" | shasum -a 256 | awk '{print $1}'
  else
    printf ''
  fi
}

_PUBLISH_EVENT_START_MS=$(date +%s%3N 2>/dev/null || echo "")
_PUBLISH_EVENT_RECORD_ID=""
_PUBLISH_EVENT_AUTHORITY_BEFORE=""
_PUBLISH_EVENT_AUTHORITY_AFTER=""
_PUBLISH_EVENT_SOURCE_DIGEST=""
_PUBLISH_EVENT_ARTIFACT_PATH=""
_PUBLISH_EVENT_ARTIFACT_DIGEST=""
_PUBLISH_EVENT_REASON_HASH=""
_PUBLISH_EVENT_REASON_PREVIEW=""
_PUBLISH_EVENT_DRY_RUN="false"

_wisdom_publish_emit_observability() {
  local rc=$?
  local status="success"
  [[ "$rc" -ne 0 ]] && status="failed"

  local duration_ms_json="null"
  if [[ -n "${_PUBLISH_EVENT_START_MS:-}" ]]; then
    local now_ms
    now_ms=$(date +%s%3N 2>/dev/null || echo "")
    if [[ -n "$now_ms" ]]; then
      duration_ms_json=$((now_ms - _PUBLISH_EVENT_START_MS))
    fi
  fi

  local payload='{}'
  payload=$(jq -nc \
    --arg record_id "${_PUBLISH_EVENT_RECORD_ID:-}" \
    --arg authority_before "${_PUBLISH_EVENT_AUTHORITY_BEFORE:-}" \
    --arg authority_after "${_PUBLISH_EVENT_AUTHORITY_AFTER:-}" \
    --arg source_digest "${_PUBLISH_EVENT_SOURCE_DIGEST:-}" \
    --arg artifact_path "${_PUBLISH_EVENT_ARTIFACT_PATH:-}" \
    --arg artifact_digest "${_PUBLISH_EVENT_ARTIFACT_DIGEST:-}" \
    --arg reason_hash "${_PUBLISH_EVENT_REASON_HASH:-}" \
    --arg reason_preview "${_PUBLISH_EVENT_REASON_PREVIEW:-}" \
    --arg dry_run "${_PUBLISH_EVENT_DRY_RUN:-false}" \
    --argjson duration_ms "$duration_ms_json" \
    '{
      record_id: (if $record_id == "" then null else $record_id end),
      authority_before: (if $authority_before == "" then null else $authority_before end),
      authority_after: (if $authority_after == "" then null else $authority_after end),
      source_digest: (if $source_digest == "" then null else $source_digest end),
      artifact_path: (if $artifact_path == "" then null else $artifact_path end),
      artifact_digest: (if $artifact_digest == "" then null else $artifact_digest end),
      reason_hash: (if $reason_hash == "" then null else $reason_hash end),
      reason_preview: (if $reason_preview == "" then null else $reason_preview end),
      duration_ms: $duration_ms,
      dry_run: ($dry_run == "true")
    }' 2>/dev/null) || payload='{}'

  wisdom_emit_event "wisdom.promote.publish" "$status" "$payload"
}

trap _wisdom_publish_emit_observability EXIT

usage() {
  cat >&2 <<'EOF'
Usage: wisdom-publish.sh --id ID [OPTIONS]

Required:
  --id ID                  Wisdom entry ID to publish

Optional:
  --scope SCOPE            Narrow search to scope (system|project|plan)
  --project-id PID         Project ID (required when scope=project|plan)
  --type TYPE              Manifest type for derivative artifact
                           (deployment|topology|env-caveat|runbook|provider-gotcha|
                            conventions|cross-repo|preferences|anti-pattern|
                            ownership|observability|rollout-state)
  --reason TEXT            Audit reason for the publication
  --manifest-scope SCOPE   Override manifest scope (system|workspace|project)
  --emit-manifest          Emit a derivative manifest file
  --dry-run                Show changes without writing
  --help, -h               Show this help

Exit codes:
  0  Published successfully
  1  Entry not found or un-publishable (stale/superseded/retracted)
  2  Bad arguments
EOF
  exit 2
}

WISDOM_ID=""
SCOPE=""
PROJECT_ID=""
MANIFEST_TYPE=""
REASON=""
MANIFEST_SCOPE=""
EMIT_MANIFEST=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --id)           WISDOM_ID="$2"; shift 2 ;;
    --scope)        SCOPE="$2"; shift 2 ;;
    --project-id)   PROJECT_ID="$2"; shift 2 ;;
    --type)         MANIFEST_TYPE="$2"; shift 2 ;;
    --reason)       REASON="$2"; shift 2 ;;
    --manifest-scope) MANIFEST_SCOPE="$2"; shift 2 ;;
    --emit-manifest) EMIT_MANIFEST=true; shift ;;
    --dry-run)      DRY_RUN=true; shift ;;
    --help|-h)      usage ;;
    *)
      if [[ -z "$WISDOM_ID" && "$1" != --* ]]; then
        WISDOM_ID="$1"
        shift
      else
        echo "ERROR: Unknown option: $1" >&2
        usage
      fi
      ;;
  esac
done

[[ -z "$WISDOM_ID" ]] && { echo "ERROR: --id is required" >&2; usage; }

_PUBLISH_EVENT_RECORD_ID="$WISDOM_ID"
_PUBLISH_EVENT_DRY_RUN="$DRY_RUN"

reason_for_event="${REASON:-published}"
_PUBLISH_EVENT_REASON_HASH=$(hash_text_sha256 "$reason_for_event")
_PUBLISH_EVENT_REASON_PREVIEW=$(wisdom_redact_preview "$reason_for_event")

STORE_PATH=""
if [[ -n "$SCOPE" ]]; then
  if [[ "$SCOPE" == "project" || "$SCOPE" == "plan" ]] && [[ -z "$PROJECT_ID" ]]; then
    echo "ERROR: --project-id is required for scope='$SCOPE'" >&2
    exit 2
  fi
  STORE_PATH=$(wisdom_get_store_path "$SCOPE" "$PROJECT_ID") || exit 2
fi

ENTRY_JSON=""
ENTRY_STORE=""

if [[ -n "$STORE_PATH" && -f "$STORE_PATH" ]]; then
  found=$(wisdom_read_entry "$WISDOM_ID" "$STORE_PATH" 2>/dev/null || true)
  if [[ -n "$found" ]]; then
    ENTRY_JSON="$found"
    ENTRY_STORE="$STORE_PATH"
  fi
else
  for store in ~/.sisyphus/wisdom/system.jsonl ~/.sisyphus/wisdom/project.jsonl; do
    if [[ -f "$store" ]]; then
      found=$(wisdom_read_entry "$WISDOM_ID" "$store" 2>/dev/null || true)
      if [[ -n "$found" ]]; then
        ENTRY_JSON="$found"
        ENTRY_STORE="$store"
        break
      fi
    fi
  done

  if [[ -z "$ENTRY_JSON" ]]; then
    for plan_store in ~/.sisyphus/wisdom/plans/*.jsonl; do
      if [[ -f "$plan_store" ]]; then
        found=$(wisdom_read_entry "$WISDOM_ID" "$plan_store" 2>/dev/null || true)
        if [[ -n "$found" ]]; then
          ENTRY_JSON="$found"
          ENTRY_STORE="$plan_store"
          break
        fi
      fi
    done
  fi
fi

[[ -z "$ENTRY_JSON" ]] && { echo "ERROR: Wisdom entry '$WISDOM_ID' not found" >&2; exit 1; }

ENTRY_AUTHORITY=$(echo "$ENTRY_JSON" | jq -r '.authority // "candidate"')
ENTRY_STATUS=$(echo "$ENTRY_JSON" | jq -r '.status // "active"')
_PUBLISH_EVENT_AUTHORITY_BEFORE="$ENTRY_AUTHORITY"

if [[ "$ENTRY_STATUS" == "superseded" || "$ENTRY_STATUS" == "retracted" ]]; then
  echo "ERROR: Entry has status='$ENTRY_STATUS', cannot publish" >&2
  exit 1
fi

if [[ "$ENTRY_AUTHORITY" == "stale" ]]; then
  echo "ERROR: Entry authority is stale, cannot publish" >&2
  exit 1
elif [[ "$ENTRY_AUTHORITY" == "candidate" ]]; then
  echo "WARNING: Publishing candidate entry without prior verification" >&2
elif [[ "$ENTRY_AUTHORITY" == "published" ]]; then
  echo "INFO: Entry is already published; updating publication metadata" >&2
fi

_PUBLISH_EVENT_AUTHORITY_AFTER="published"

compute_source_digest() {
  local record="$1"
  echo "$record" | jq -r '
    [.body // "", .title // "", (.tags // [] | sort | join(",")), .type // ""]
    | join("\n")
  ' | sha256sum | awk '{print $1}'
}

SOURCE_DIGEST=$(compute_source_digest "$ENTRY_JSON")
_PUBLISH_EVENT_SOURCE_DIGEST="$SOURCE_DIGEST"

NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

ENTRY_SCOPE=$(echo "$ENTRY_JSON" | jq -r '.scope // "system"')
MANIFEST_SCOPE="${MANIFEST_SCOPE:-$ENTRY_SCOPE}"

if [[ "$MANIFEST_SCOPE" == "plan" ]]; then
  MANIFEST_SCOPE="project"
fi

VALID_MANIFEST_SCOPES=("system" "workspace" "project")
scope_valid=false
for s in "${VALID_MANIFEST_SCOPES[@]}"; do
  if [[ "$MANIFEST_SCOPE" == "$s" ]]; then
    scope_valid=true
    break
  fi
done
if [[ "$scope_valid" == false ]]; then
  echo "ERROR: Invalid manifest scope: $MANIFEST_SCOPE" >&2
  exit 2
fi

if [[ -z "$MANIFEST_TYPE" ]]; then
  ENTRY_TYPE=$(echo "$ENTRY_JSON" | jq -r '.type // "fact"')
  case "$ENTRY_TYPE" in
    gotcha)   MANIFEST_TYPE="provider-gotcha" ;;
    pattern)  MANIFEST_TYPE="conventions" ;;
    decision) MANIFEST_TYPE="cross-repo" ;;
    warning)  MANIFEST_TYPE="anti-pattern" ;;
    fact|*)   MANIFEST_TYPE="deployment" ;;
  esac
fi

MANIFEST_ID=""
MANIFEST_FILE=""
ARTIFACT_PATH=""

if [[ "$EMIT_MANIFEST" == true ]]; then
  ENTRY_BODY=$(echo "$ENTRY_JSON" | jq -r '.body // ""')
  ENTRY_TAGS=$(echo "$ENTRY_JSON" | jq -r '.tags // [] | join(",")')
  [[ -z "$ENTRY_TAGS" || "$ENTRY_TAGS" == "[]" ]] && ENTRY_TAGS="published"
  ENTRY_TITLE=$(echo "$ENTRY_JSON" | jq -r '.title // (.body // "Published wisdom" | split("\n")[0] | .[0:80])')

  if [[ "$DRY_RUN" == true ]]; then
    echo "[DRY-RUN] Would emit manifest:"
    echo "  Title: $ENTRY_TITLE"
    echo "  Type:  $MANIFEST_TYPE"
    echo "  Scope: $MANIFEST_SCOPE"
    echo "  Tags:  $ENTRY_TAGS"
  else
    MANIFEST_OUTPUT=$("${SCRIPT_DIR}/manifest-write.sh" \
      --title "$ENTRY_TITLE" \
      --type "$MANIFEST_TYPE" \
      --scope "$MANIFEST_SCOPE" \
      --body "$ENTRY_BODY" \
      --owner "user" \
      --tags "$ENTRY_TAGS" \
      --validation-method "published from wisdom" \
      --freshness-days 90 2>/dev/null) || {
        echo "WARNING: manifest-write.sh failed (file may already exist); continuing with wisdom record update only" >&2
        MANIFEST_OUTPUT=""
      }

    if [[ -n "$MANIFEST_OUTPUT" ]]; then
      MANIFEST_ID="$(printf '%s' "$MANIFEST_OUTPUT" | tail -n1 | tr -d '[:space:]')"

      MANIFEST_SLUG=$(echo "$ENTRY_TITLE" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g; s/--*/-/g; s/^-//;s/-$//')
      MANIFEST_FILE="${KNOWLEDGE_MANIFESTS_DIR}/${MANIFEST_SCOPE}/${MANIFEST_SLUG}.md"
      if [[ -f "$MANIFEST_FILE" ]]; then
        sed -i "s/^provenance:.*/provenance: published-from-wisdom:${WISDOM_ID}/" "$MANIFEST_FILE"
      fi
      ARTIFACT_PATH="$MANIFEST_FILE"
    fi
  fi
else
  ARTIFACT_PATH="knowledge://wisdom/${WISDOM_ID}/published/${NOW}"
fi

_PUBLISH_EVENT_ARTIFACT_PATH="$ARTIFACT_PATH"
if [[ -n "$ARTIFACT_PATH" && -f "$ARTIFACT_PATH" ]]; then
  _PUBLISH_EVENT_ARTIFACT_DIGEST=$(wisdom_sha256_file "$ARTIFACT_PATH" 2>/dev/null || true)
fi

PUBLISHED_ARTIFACT=$(jq -n \
  --arg path "$ARTIFACT_PATH" \
  --arg created "$NOW" \
  --arg digest "$SOURCE_DIGEST" \
  '{artifact_path: $path, created_at: $created, source_digest: $digest}')

UPDATED_JSON=$(echo "$ENTRY_JSON" | jq \
  --arg auth "published" \
  --arg at "$NOW" \
  --arg prov "publish-export" \
  --argjson artifact "$PUBLISHED_ARTIFACT" '
    .authority = $auth
    | .verified_at = $at
    | .status = "active"
    | .provenance = $prov
    | .metadata.published_artifacts = ((.metadata.published_artifacts // []) + [$artifact])
')

UPDATED_JSON=$(wisdom_normalize_record "$UPDATED_JSON") || { echo "ERROR: normalization failed" >&2; exit 1; }
if ! wisdom_validate_canonical "$UPDATED_JSON"; then
  echo "ERROR: updated record failed canonical validation" >&2
  exit 1
fi

if [[ "$DRY_RUN" == true ]]; then
  echo "=== DRY-RUN: Updated record ==="
  echo "$UPDATED_JSON" | jq .
  echo ""
  echo "Dry run complete. No changes written."
  exit 0
fi

if [[ -n "$ENTRY_STORE" ]]; then
  wisdom_update_entry "$WISDOM_ID" "$ENTRY_STORE" "$UPDATED_JSON"
fi

mkdir -p "${HOME}/.sisyphus/wisdom"
  LOG_ENTRY=$(jq -n -c \
    --arg ts "$NOW" \
    --arg wid "$WISDOM_ID" \
    --arg mid "$MANIFEST_ID" \
    --arg path "$ARTIFACT_PATH" \
    --arg reason "${REASON:-published}" \
    --arg actor "user" \
    --arg digest "$SOURCE_DIGEST" \
    '{
    timestamp: $ts,
    wisdom_id: $wid,
    manifest_id: $mid,
    manifest_path: $path,
    reason: $reason,
    actor: $actor,
    source_digest: $digest,
    action: "publish"
  }')

  printf '%s\n' "$LOG_ENTRY" >> "${HOME}/.sisyphus/wisdom/promotion-log.jsonl"

echo "=== Publish Complete ==="
echo "Wisdom: $WISDOM_ID"
echo "Authority: published"
echo "Verified at: $NOW"
if [[ -n "$MANIFEST_ID" ]]; then
  echo "Manifest: $MANIFEST_ID"
  echo "File: $MANIFEST_FILE"
fi
echo "Artifacts tracked: $(echo "$UPDATED_JSON" | jq '.metadata.published_artifacts | length')"
echo "Source digest: $SOURCE_DIGEST"
if [[ -n "$REASON" ]]; then
  echo "Reason: $REASON"
fi
