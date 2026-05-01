#!/usr/bin/env bash
set -euo pipefail

# wisdom-migrate.sh — Canonical Wisdom migration/backfill with backup + restore support.
#
# Phases:
#   1) Backup existing Wisdom/manifests/skills/config references into timestamped tarball
#   2) Normalize legacy Wisdom JSONL records in place via wisdom_normalize_record
#   3) Import manifest records into canonical Wisdom with idempotent upsert semantics
#
# Notes:
# - Runtime canonical store remains Wisdom JSONL. Manifests are imported as derivative sources.
# - Restore helper script is generated next to each backup tarball.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

source "${SCRIPT_DIR}/wisdom-common.sh"
wisdom_require_jq

SISYPHUS_HOME="${SISYPHUS_HOME:-${HOME}/.sisyphus}"

CANONICAL_WISDOM_ROOT="${WISDOM_MIGRATION_CANONICAL_WISDOM_ROOT:-${SISYPHUS_HOME}/wisdom}"
LEGACY_WISDOM_ROOT="${WISDOM_MIGRATION_LEGACY_WISDOM_ROOT:-${SISYPHUS_HOME}/data/wisdom}"
MANIFEST_ROOT="${WISDOM_MIGRATION_MANIFEST_ROOT:-${SISYPHUS_HOME}/knowledge/manifests}"
BACKUP_ROOT="${WISDOM_MIGRATION_BACKUP_ROOT:-${SISYPHUS_HOME}/backups/wisdom-migration}"
BACKUP_REF_FILE="${WISDOM_MIGRATION_BACKUP_REF_FILE:-${SISYPHUS_HOME}/wisdom/.migration-last-backup-path}"

SKILL_WISDOM_PATH="${WISDOM_MIGRATION_SKILL_WISDOM_PATH:-${HOME}/.config/opencode/skills/wisdom}"
AGENTS_PATH="${WISDOM_MIGRATION_AGENTS_PATH:-${REPO_ROOT}/AGENTS.md}"
OH_MY_OPENAGENT_PATH="${WISDOM_MIGRATION_OH_MY_OPENAGENT_PATH:-${REPO_ROOT}/configs/oh-my-openagent/oh-my-openagent.json}"

PRIMARY_WISDOM_ROOT=""
LAST_BACKUP_TARBALL=""

NORMALIZED_FILES=0
NORMALIZED_RECORDS=0
IMPORT_CREATED=0
IMPORT_MERGED=0
IMPORT_REPLACED=0
IMPORT_SKIPPED=0

usage() {
    cat >&2 <<'EOF'
Usage: wisdom-migrate.sh [OPTIONS]

Runs Wisdom migration phases: backup, normalize, import.

Options:
  --skip-backup            Skip backup phase
  --backup-only            Run only backup phase
  --normalize-only         Run only normalize phase
  --import-only            Run only import phase
  --restore TARBALL        Restore backup tarball and exit
  --restore-target DIR     Restore destination root (default: /)
  --help, -h               Show this help

Environment overrides:
  SISYPHUS_HOME
  WISDOM_MIGRATION_CANONICAL_WISDOM_ROOT
  WISDOM_MIGRATION_LEGACY_WISDOM_ROOT
  WISDOM_MIGRATION_MANIFEST_ROOT
  WISDOM_MIGRATION_BACKUP_ROOT
  WISDOM_MIGRATION_BACKUP_REF_FILE
  WISDOM_MIGRATION_SKILL_WISDOM_PATH
  WISDOM_MIGRATION_AGENTS_PATH
  WISDOM_MIGRATION_OH_MY_OPENAGENT_PATH
EOF
}

log_info() {
    wisdom_log INFO "$*"
}

log_warn() {
    wisdom_log WARN "$*"
}

log_error() {
    wisdom_log ERROR "$*"
}

timestamp_now() {
    date -u +%Y-%m-%dT%H:%M:%SZ
}

canonicalize_iso() {
    local raw="${1:-}"
    if [[ -z "$raw" || "$raw" == "null" ]]; then
        printf ''
        return 0
    fi
    if [[ "$raw" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        printf '%sT00:00:00Z' "$raw"
        return 0
    fi
    if [[ "$raw" =~ Z$ || "$raw" =~ [+-][0-9]{2}:[0-9]{2}$ ]]; then
        printf '%s' "$raw"
        return 0
    fi
    if [[ "$raw" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]]; then
        printf '%sZ' "$raw"
        return 0
    fi
    printf ''
}

status_rank() {
    case "${1:-}" in
        active) printf '4' ;;
        stale) printf '3' ;;
        superseded) printf '2' ;;
        retracted) printf '1' ;;
        *) printf '0' ;;
    esac
}

choose_higher_status() {
    local left="${1:-}"
    local right="${2:-}"
    local left_rank right_rank
    left_rank=$(status_rank "$left")
    right_rank=$(status_rank "$right")
    if (( left_rank >= right_rank )); then
        printf '%s' "$left"
    else
        printf '%s' "$right"
    fi
}

choose_higher_authority() {
    local left="$(wisdom_normalize_authority "${1:-}")"
    local right="$(wisdom_normalize_authority "${2:-}")"
    local left_rank right_rank
    left_rank=$(wisdom_authority_rank "$left")
    right_rank=$(wisdom_authority_rank "$right")
    if (( left_rank >= right_rank )); then
        printf '%s' "$left"
    else
        printf '%s' "$right"
    fi
}

canonical_fingerprint() {
    local record_json="$1"
    printf '%s' "$record_json" | jq -r '
        [
            (.scope // ""),
            (.type // ""),
            (.title // ""),
            (.body // "")
        ]
        | map(
            tostring
            | ascii_downcase
            | gsub("\\s+"; " ")
            | gsub("^\\s+|\\s+$"; "")
        )
        | join("\u001f")
    ' | sha256sum | cut -d' ' -f1
}

map_manifest_type() {
    case "${1:-}" in
        provider-gotcha|env-caveat|anti-pattern)
            printf 'warning'
            ;;
        conventions|runbook|preferences)
            printf 'pattern'
            ;;
        cross-repo)
            printf 'decision'
            ;;
        deployment|topology|ownership|observability|rollout-state)
            printf 'fact'
            ;;
        *)
            printf 'fact'
            ;;
    esac
}

map_manifest_status() {
    case "${1:-}" in
        ""|active|verified|candidate)
            printf 'active'
            ;;
        deprecated|stale)
            printf 'stale'
            ;;
        superseded)
            printf 'superseded'
            ;;
        retracted)
            printf 'retracted'
            ;;
        *)
            printf 'active'
            ;;
    esac
}

choose_primary_wisdom_root() {
    local canonical_has_data=0
    local legacy_has_data=0

    if [[ -d "$CANONICAL_WISDOM_ROOT" ]]; then
        if find "$CANONICAL_WISDOM_ROOT" -type f -name '*.jsonl' -print -quit | grep -q .; then
            canonical_has_data=1
        fi
    fi
    if [[ -d "$LEGACY_WISDOM_ROOT" ]]; then
        if find "$LEGACY_WISDOM_ROOT" -type f -name '*.jsonl' -print -quit | grep -q .; then
            legacy_has_data=1
        fi
    fi

    if [[ "$canonical_has_data" -eq 1 ]]; then
        PRIMARY_WISDOM_ROOT="$CANONICAL_WISDOM_ROOT"
    elif [[ "$legacy_has_data" -eq 1 ]]; then
        PRIMARY_WISDOM_ROOT="$LEGACY_WISDOM_ROOT"
    elif [[ -d "$CANONICAL_WISDOM_ROOT" || -f "$CANONICAL_WISDOM_ROOT/system.jsonl" ]]; then
        PRIMARY_WISDOM_ROOT="$CANONICAL_WISDOM_ROOT"
    elif [[ -d "$LEGACY_WISDOM_ROOT" || -f "$LEGACY_WISDOM_ROOT/system.jsonl" ]]; then
        PRIMARY_WISDOM_ROOT="$LEGACY_WISDOM_ROOT"
    else
        PRIMARY_WISDOM_ROOT="$CANONICAL_WISDOM_ROOT"
        mkdir -p "$PRIMARY_WISDOM_ROOT"
    fi

    export WISDOM_ROOT="$PRIMARY_WISDOM_ROOT"
    log_info "Primary Wisdom root: $PRIMARY_WISDOM_ROOT"
}

list_store_files_for_root() {
    local root="$1"
    [[ -d "$root" ]] || return 0
    find "$root" -type f -name '*.jsonl' | sort
}

list_primary_store_files() {
    list_store_files_for_root "$PRIMARY_WISDOM_ROOT"
}

ensure_store_exists() {
    local store_path="$1"
    mkdir -p "$(dirname "$store_path")"
    touch "$store_path"
}

store_for_manifest_scope() {
    local manifest_scope="$1"
    case "$manifest_scope" in
        system)
            printf '%s/system.jsonl' "$PRIMARY_WISDOM_ROOT"
            ;;
        workspace)
            printf '%s/projects/workspace-manifests.jsonl' "$PRIMARY_WISDOM_ROOT"
            ;;
        project)
            printf '%s/projects/project-manifests.jsonl' "$PRIMARY_WISDOM_ROOT"
            ;;
        *)
            printf '%s/system.jsonl' "$PRIMARY_WISDOM_ROOT"
            ;;
    esac
}

parse_manifest_json() {
    local manifest_path="$1"
    python3 - "$manifest_path" <<'PY'
import json
import pathlib
import re
import sys

import yaml

path = pathlib.Path(sys.argv[1]).resolve()
text = path.read_text(encoding="utf-8")
frontmatter = {}
body = text

if text.startswith("---"):
    match = re.match(r"^---\s*\n(.*?)\n---\s*\n?(.*)$", text, flags=re.S)
    if match:
        try:
            parsed = yaml.safe_load(match.group(1))
            if isinstance(parsed, dict):
                frontmatter = parsed
        except Exception:
            frontmatter = {}
        body = match.group(2)

print(json.dumps({
    "path": str(path),
    "frontmatter": frontmatter,
    "body": body,
}))
PY
}

manifest_scope_hint_from_path() {
    local manifest_path="$1"
    case "$manifest_path" in
        *"/manifests/system/"*) printf 'system' ;;
        *"/manifests/workspace/"*) printf 'workspace' ;;
        *"/manifests/project/"*) printf 'project' ;;
        *) printf 'system' ;;
    esac
}

normalize_store_file() {
    local store_path="$1"
    [[ -f "$store_path" ]] || return 0

    local tmp_file
    tmp_file=$(mktemp "${store_path}.norm.XXXXXX")

    local changed=0
    local file_normalized=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ -z "$line" ]]; then
            continue
        fi

        if ! printf '%s' "$line" | jq empty >/dev/null 2>&1; then
            log_warn "Skipping invalid JSON line in $store_path"
            printf '%s\n' "$line" >> "$tmp_file"
            continue
        fi

        local normalized
        normalized=$(wisdom_normalize_record "$line") || {
            log_warn "wisdom_normalize_record failed for entry in $store_path; preserving original line"
            printf '%s\n' "$line" >> "$tmp_file"
            continue
        }

        if ! wisdom_validate_canonical "$normalized" >/dev/null 2>&1; then
            log_warn "Canonical validation failed for normalized entry in $store_path; preserving original line"
            printf '%s\n' "$line" >> "$tmp_file"
            continue
        fi

        if [[ "$normalized" != "$line" ]]; then
            changed=1
            file_normalized=$((file_normalized + 1))
        fi

        printf '%s\n' "$normalized" >> "$tmp_file"
    done < "$store_path"

    if [[ "$changed" -eq 1 ]]; then
        local lockfile="${store_path}.lock"
        if command -v flock >/dev/null 2>&1; then
            if ! (
                flock -w 10 200 || exit 1
                mv -f "$tmp_file" "$store_path"
            ) 200>"$lockfile"; then
                rm -f "$tmp_file"
                log_error "Failed to atomically rewrite normalized store: $store_path"
                return 1
            fi
        else
            mv -f "$tmp_file" "$store_path"
        fi
        NORMALIZED_FILES=$((NORMALIZED_FILES + 1))
        NORMALIZED_RECORDS=$((NORMALIZED_RECORDS + file_normalized))
    else
        rm -f "$tmp_file"
    fi
}

pick_best_match_from_stream() {
    local stream="$1"
    if [[ -z "${stream//[[:space:]]/}" ]]; then
        return 1
    fi
    printf '%s\n' "$stream" | jq -sc '
        map(select(type == "object"))
        | if length == 0 then empty else
            sort_by([
                -(if .record.status == "active" then 4 elif .record.status == "stale" then 3 elif .record.status == "superseded" then 2 elif .record.status == "retracted" then 1 else 0 end),
                -(if .record.authority == "published" then 3 elif .record.authority == "verified" then 2 elif .record.authority == "candidate" then 1 else 0 end),
                -(try (.record.created | fromdateiso8601) catch 0),
                (.record.id // "")
            ])
            | .[0]
          end
    '
}

find_best_match_by_legacy_manifest_id() {
    local legacy_id="$1"
    [[ -n "$legacy_id" ]] || return 1

    local stream=""
    local store
    while IFS= read -r store; do
        [[ -f "$store" ]] || continue
        local matches
        matches=$(jq -c --arg id "$legacy_id" --arg store "$store" '
            select(.metadata.legacy_manifest_id == $id)
            | {store_path: $store, record: .}
        ' "$store" 2>/dev/null || true)
        if [[ -n "$matches" ]]; then
            stream+="$matches"$'\n'
        fi
    done < <(list_primary_store_files)

    pick_best_match_from_stream "$stream"
}

find_best_match_by_legacy_manifest_path() {
    local manifest_path="$1"
    [[ -n "$manifest_path" ]] || return 1

    local stream=""
    local store
    while IFS= read -r store; do
        [[ -f "$store" ]] || continue
        local matches
        matches=$(jq -c --arg path "$manifest_path" --arg store "$store" '
            select(.metadata.legacy_manifest_path == $path)
            | {store_path: $store, record: .}
        ' "$store" 2>/dev/null || true)
        if [[ -n "$matches" ]]; then
            stream+="$matches"$'\n'
        fi
    done < <(list_primary_store_files)

    pick_best_match_from_stream "$stream"
}

find_best_match_by_fingerprint() {
    local target_fingerprint="$1"
    [[ -n "$target_fingerprint" ]] || return 1

    local stream=""
    local store
    while IFS= read -r store; do
        [[ -f "$store" ]] || continue
        while IFS= read -r line || [[ -n "$line" ]]; do
            [[ -n "$line" ]] || continue
            if ! printf '%s' "$line" | jq empty >/dev/null 2>&1; then
                continue
            fi
            local fp
            fp=$(canonical_fingerprint "$line")
            if [[ "$fp" == "$target_fingerprint" ]]; then
                local wrapped
                wrapped=$(jq -nc --arg store "$store" --argjson record "$line" '{store_path:$store, record:$record}')
                stream+="$wrapped"$'\n'
            fi
        done < "$store"
    done < <(list_primary_store_files)

    pick_best_match_from_stream "$stream"
}

merge_duplicate_records() {
    local existing_json="$1"
    local incoming_json="$2"

    local existing_authority existing_status incoming_authority incoming_status selected_authority selected_status
    existing_authority=$(printf '%s' "$existing_json" | jq -r '.authority // "candidate"')
    existing_status=$(printf '%s' "$existing_json" | jq -r '.status // "active"')
    incoming_authority=$(printf '%s' "$incoming_json" | jq -r '.authority // "candidate"')
    incoming_status=$(printf '%s' "$incoming_json" | jq -r '.status // "active"')

    selected_authority=$(choose_higher_authority "$existing_authority" "$incoming_authority")
    selected_status=$(choose_higher_status "$existing_status" "$incoming_status")

    local merged
    merged=$(printf '%s' "$existing_json" | jq -c \
        --arg auth "$selected_authority" \
        --arg status "$selected_status" \
        --argjson incoming "$incoming_json" '
        . as $existing
        | .tags = ((($existing.tags // []) + ($incoming.tags // [])) | map(select(type == "string") | ascii_downcase) | unique)
        | .authority = $auth
        | .status = $status
        | .provenance = (if $existing.provenance == "manifest-import" or $incoming.provenance == "manifest-import" then "manifest-import" else ($existing.provenance // $incoming.provenance // "manual") end)
        | .title = ($existing.title // $incoming.title)
        | .origin_session = ($existing.origin_session // $incoming.origin_session // null)
        | .review_due = ($existing.review_due // $incoming.review_due // null)
        | .verified_at = (if $auth == "candidate" then null else ($existing.verified_at // $incoming.verified_at // null) end)
        | .metadata = {
            owner: ($existing.metadata.owner // $incoming.metadata.owner // null),
            sensitivity: ($existing.metadata.sensitivity // $incoming.metadata.sensitivity // null),
            validation_method: ($existing.metadata.validation_method // $incoming.metadata.validation_method // null),
            last_verified: ($existing.metadata.last_verified // $incoming.metadata.last_verified // null),
            freshness_days: ($existing.metadata.freshness_days // $incoming.metadata.freshness_days // null),
            legacy_manifest_id: ($existing.metadata.legacy_manifest_id // $incoming.metadata.legacy_manifest_id // null),
            legacy_manifest_path: ($existing.metadata.legacy_manifest_path // $incoming.metadata.legacy_manifest_path // null),
            legacy_authority: ($existing.metadata.legacy_authority // $incoming.metadata.legacy_authority // null),
            source_kind: ($existing.metadata.source_kind // $incoming.metadata.source_kind // null),
            published_artifacts: (
                (($existing.metadata.published_artifacts // []) + ($incoming.metadata.published_artifacts // []))
                | if type == "array" then unique_by((.artifact_path // "") + "|" + (.source_digest // "")) else [] end
            )
        }
    ')

    wisdom_normalize_record "$merged"
}

build_import_record() {
    local manifest_json="$1"
    local import_time="$2"

    local manifest_path scope_hint manifest_scope manifest_type mapped_type status_raw mapped_status
    local title body legacy_manifest_id legacy_authority source_field
    local origin_session created_raw modified_raw created_ts review_due_raw review_due_ts
    local verified_raw verified_ts owner sensitivity validation_method source_kind superseded_by
    local tags_json freshness_days_json published_artifacts_json

    manifest_path=$(printf '%s' "$manifest_json" | jq -r '.path')
    scope_hint=$(manifest_scope_hint_from_path "$manifest_path")
    manifest_scope=$(printf '%s' "$manifest_json" | jq -r --arg hint "$scope_hint" '.frontmatter.scope // $hint | tostring | ascii_downcase')

    manifest_type=$(printf '%s' "$manifest_json" | jq -r '.frontmatter.type // "deployment" | tostring | ascii_downcase')
    mapped_type=$(map_manifest_type "$manifest_type")

    status_raw=$(printf '%s' "$manifest_json" | jq -r '.frontmatter.status // "active" | tostring | ascii_downcase')
    mapped_status=$(map_manifest_status "$status_raw")

    title=$(printf '%s' "$manifest_json" | jq -r '.frontmatter.title // empty')
    body=$(printf '%s' "$manifest_json" | jq -r '.body // ""')

    legacy_manifest_id=$(printf '%s' "$manifest_json" | jq -r '.frontmatter.id // empty')
    if [[ -z "$legacy_manifest_id" ]]; then
        legacy_manifest_id="$(basename "$manifest_path" .md)"
    fi

    legacy_authority=$(printf '%s' "$manifest_json" | jq -r '.frontmatter.authority // "manifest"')
    origin_session=$(printf '%s' "$manifest_json" | jq -r '.frontmatter.origin_session // empty')

    created_raw=$(printf '%s' "$manifest_json" | jq -r '.frontmatter.created // empty')
    modified_raw=$(printf '%s' "$manifest_json" | jq -r '.frontmatter.modified // empty')
    created_ts=$(canonicalize_iso "$created_raw")
    if [[ -z "$created_ts" ]]; then
        created_ts=$(canonicalize_iso "$modified_raw")
    fi
    if [[ -z "$created_ts" ]]; then
        created_ts="$import_time"
    fi

    verified_raw=$(printf '%s' "$manifest_json" | jq -r '.frontmatter.last_verified // empty')
    verified_ts=$(canonicalize_iso "$verified_raw")
    if [[ -z "$verified_ts" ]]; then
        verified_ts="$created_ts"
    fi
    if [[ -z "$verified_ts" ]]; then
        verified_ts="$import_time"
    fi

    review_due_raw=$(printf '%s' "$manifest_json" | jq -r '.frontmatter.review_due // empty')
    review_due_ts=$(canonicalize_iso "$review_due_raw")

    owner=$(printf '%s' "$manifest_json" | jq -r '.frontmatter.owner // empty')
    sensitivity=$(printf '%s' "$manifest_json" | jq -r '.frontmatter.sensitivity // empty')
    validation_method=$(printf '%s' "$manifest_json" | jq -r '.frontmatter.validation_method // empty')
    source_field=$(printf '%s' "$manifest_json" | jq -r '.frontmatter.source // empty')
    source_kind=$(printf '%s' "$manifest_json" | jq -r '.frontmatter.category // empty')
    if [[ -z "$source_kind" ]]; then
        source_kind="$manifest_type"
    fi
    superseded_by=$(printf '%s' "$manifest_json" | jq -r '.frontmatter.superseded_by // empty')

    tags_json=$(printf '%s' "$manifest_json" | jq -c '
        (.frontmatter.tags // [])
        | if type == "array" then .
          elif type == "string" then split(",")
          else []
          end
        | map(tostring | ascii_downcase | gsub("^\\s+|\\s+$"; ""))
        | map(select(length > 0))
        | unique
    ')

    freshness_days_json=$(printf '%s' "$manifest_json" | jq -c '
        if (.frontmatter.freshness_days | type) == "number" then .frontmatter.freshness_days
        elif (.frontmatter.freshness_days | type) == "string" and (.frontmatter.freshness_days | test("^[0-9]+$")) then (.frontmatter.freshness_days | tonumber)
        else null
        end
    ')

    local fingerprint_seed
    fingerprint_seed=$(jq -nc \
        --arg scope "$manifest_scope" \
        --arg type "$mapped_type" \
        --arg title "$title" \
        --arg body "$body" \
        '{scope:$scope,type:$type,title:(if $title=="" then null else $title end),body:$body}')

    local source_digest
    source_digest=$(canonical_fingerprint "$fingerprint_seed")

    published_artifacts_json=$(jq -nc \
        --arg path "$manifest_path" \
        --arg created_at "$import_time" \
        --arg digest "$source_digest" \
        '[{artifact_path:$path,created_at:$created_at,source_digest:$digest}]')

    local import_scope
    case "$manifest_scope" in
        workspace|project)
            import_scope="project"
            ;;
        *)
            import_scope="system"
            ;;
    esac

    local record
    record=$(jq -nc \
        --arg id "$(wisdom_generate_id)" \
        --arg type "$mapped_type" \
        --arg scope "$import_scope" \
        --arg title "$title" \
        --argjson tags "$tags_json" \
        --arg body "$body" \
        --arg authority "published" \
        --arg status "$mapped_status" \
        --arg provenance "manifest-import" \
        --arg origin_session "$origin_session" \
        --arg verified_at "$verified_ts" \
        --arg review_due "$review_due_ts" \
        --arg superseded_by "$superseded_by" \
        --arg owner "$owner" \
        --arg sensitivity "$sensitivity" \
        --arg validation_method "$validation_method" \
        --arg last_verified "$verified_ts" \
        --argjson freshness_days "$freshness_days_json" \
        --arg legacy_manifest_id "$legacy_manifest_id" \
        --arg legacy_manifest_path "$manifest_path" \
        --arg legacy_authority "$legacy_authority" \
        --arg source_kind "$source_kind" \
        --argjson published_artifacts "$published_artifacts_json" \
        --arg created "$created_ts" \
        --arg source "$source_field" \
        '{
            id: $id,
            type: $type,
            scope: $scope,
            title: (if $title == "" then null else $title end),
            tags: $tags,
            body: $body,
            authority: $authority,
            status: $status,
            provenance: $provenance,
            origin_session: (if $origin_session == "" then null else $origin_session end),
            verified_at: (if $verified_at == "" then null else $verified_at end),
            review_due: (if $review_due == "" then null else $review_due end),
            superseded_by: (if $status == "superseded" and $superseded_by != "" then $superseded_by else null end),
            contradicts: [],
            metadata: {
                owner: (if $owner == "" then null else $owner end),
                sensitivity: (if $sensitivity == "" then null else $sensitivity end),
                validation_method: (if $validation_method == "" then null else $validation_method end),
                last_verified: (if $last_verified == "" then null else $last_verified end),
                freshness_days: $freshness_days,
                legacy_manifest_id: (if $legacy_manifest_id == "" then null else $legacy_manifest_id end),
                legacy_manifest_path: (if $legacy_manifest_path == "" then null else $legacy_manifest_path end),
                legacy_authority: (if $legacy_authority == "" then null else $legacy_authority end),
                source_kind: (if $source_kind == "" then null else $source_kind end),
                published_artifacts: $published_artifacts
            },
            created: $created,
            accessed: 0,
            last_accessed: "",
            source: (if $source == "" then null else $source end),
            quality_score: null
        }')

    local normalized
    normalized=$(wisdom_normalize_record "$record")
    if ! wisdom_validate_canonical "$normalized" >/dev/null 2>&1; then
        log_error "Manifest-derived record failed canonical validation for: $manifest_path"
        return 1
    fi

    printf '%s\n' "$normalized"
}

append_record() {
    local record_json="$1"
    local store_path="$2"
    ensure_store_exists "$store_path"
    wisdom_append_entry "$record_json" "$store_path"
}

update_record() {
    local record_json="$1"
    local store_path="$2"
    local record_id
    record_id=$(printf '%s' "$record_json" | jq -r '.id')
    wisdom_update_entry "$record_id" "$store_path" "$record_json"
}

backup_phase() {
    mkdir -p "$BACKUP_ROOT"

    local timestamp backup_tar staging_dir
    timestamp=$(date -u +%Y%m%d-%H%M%S)
    backup_tar="${BACKUP_ROOT}/wisdom-migration-${timestamp}.tar.gz"
    staging_dir=$(mktemp -d)

    local sources=()

    if [[ -d "$LEGACY_WISDOM_ROOT" ]]; then
        sources+=("$LEGACY_WISDOM_ROOT")
    fi
    if [[ -d "$CANONICAL_WISDOM_ROOT" ]]; then
        sources+=("$CANONICAL_WISDOM_ROOT")
    fi
    if [[ -d "$MANIFEST_ROOT" ]]; then
        sources+=("$MANIFEST_ROOT")
    fi
    if [[ -e "$SKILL_WISDOM_PATH" ]]; then
        sources+=("$SKILL_WISDOM_PATH")
    fi
    if [[ -e "$AGENTS_PATH" ]]; then
        sources+=("$AGENTS_PATH")
    fi
    if [[ -e "$OH_MY_OPENAGENT_PATH" ]]; then
        sources+=("$OH_MY_OPENAGENT_PATH")
    fi

    if [[ "${#sources[@]}" -eq 0 ]]; then
        rm -rf "$staging_dir"
        log_error "Backup phase found no source paths to archive"
        return 1
    fi

    local src rel dest_parent
    for src in "${sources[@]}"; do
        [[ -e "$src" ]] || continue
        rel="${src#/}"
        dest_parent="${staging_dir}/$(dirname "$rel")"
        mkdir -p "$dest_parent"
        cp -a "$src" "${staging_dir}/${rel}"
    done

    tar -czf "$backup_tar" -C "$staging_dir" .
    rm -rf "$staging_dir"

    mkdir -p "$(dirname "$BACKUP_REF_FILE")"
    printf '%s\n' "$backup_tar" > "$BACKUP_REF_FILE"

    local restore_script
    restore_script="${backup_tar%.tar.gz}-restore.sh"
    cat > "$restore_script" <<EOF
#!/usr/bin/env bash
set -euo pipefail

TARBALL="\${1:-$backup_tar}"
TARGET_ROOT="\${2:-/}"

if [[ ! -f "\$TARBALL" ]]; then
    echo "ERROR: backup tarball not found: \$TARBALL" >&2
    exit 1
fi

mkdir -p "\$TARGET_ROOT"
tar -xzf "\$TARBALL" -C "\$TARGET_ROOT"
echo "Restored \$TARBALL into \$TARGET_ROOT"
EOF
    chmod +x "$restore_script"

    LAST_BACKUP_TARBALL="$backup_tar"
    log_info "Backup created: $backup_tar"
    log_info "Backup reference file: $BACKUP_REF_FILE"
    log_info "Restore helper script: $restore_script"
}

restore_phase() {
    local tarball="$1"
    local target_root="${2:-/}"

    if [[ ! -f "$tarball" ]]; then
        log_error "Restore tarball does not exist: $tarball"
        return 1
    fi

    mkdir -p "$target_root"
    tar -xzf "$tarball" -C "$target_root"
    log_info "Restore completed: $tarball -> $target_root"
}

normalize_phase() {
    local roots=()
    if [[ -d "$PRIMARY_WISDOM_ROOT" ]]; then
        roots+=("$PRIMARY_WISDOM_ROOT")
    fi
    if [[ -d "$LEGACY_WISDOM_ROOT" && "$LEGACY_WISDOM_ROOT" != "$PRIMARY_WISDOM_ROOT" ]]; then
        roots+=("$LEGACY_WISDOM_ROOT")
    fi

    local root store_count
    for root in "${roots[@]}"; do
        store_count=0
        while IFS= read -r _store; do
            store_count=$((store_count + 1))
        done < <(list_store_files_for_root "$root")

        if [[ "$store_count" -eq 0 ]]; then
            continue
        fi

        while IFS= read -r store; do
            [[ -f "$store" ]] || continue
            normalize_store_file "$store"
        done < <(list_store_files_for_root "$root")
    done

    log_info "Normalization completed: files_changed=$NORMALIZED_FILES records_normalized=$NORMALIZED_RECORDS"
}

import_one_manifest() {
    local manifest_file="$1"
    local import_time incoming_record target_store
    import_time="$(timestamp_now)"

    local manifest_json
    manifest_json=$(parse_manifest_json "$manifest_file")

    incoming_record=$(build_import_record "$manifest_json" "$import_time")

    local incoming_scope
    incoming_scope=$(printf '%s' "$incoming_record" | jq -r '.scope // "system"')
    case "$incoming_scope" in
        system)
            target_store="${PRIMARY_WISDOM_ROOT}/system.jsonl"
            ;;
        project)
            target_store=$(store_for_manifest_scope "$(manifest_scope_hint_from_path "$manifest_file")")
            ;;
        *)
            target_store="${PRIMARY_WISDOM_ROOT}/system.jsonl"
            ;;
    esac
    ensure_store_exists "$target_store"

    local legacy_id legacy_path incoming_fp
    legacy_id=$(printf '%s' "$incoming_record" | jq -r '.metadata.legacy_manifest_id // empty')
    legacy_path=$(printf '%s' "$incoming_record" | jq -r '.metadata.legacy_manifest_path // empty')
    incoming_fp=$(canonical_fingerprint "$incoming_record")

    local best_match=""
    if best_match=$(find_best_match_by_legacy_manifest_id "$legacy_id" 2>/dev/null); then
        :
    elif best_match=$(find_best_match_by_legacy_manifest_path "$legacy_path" 2>/dev/null); then
        :
    elif best_match=$(find_best_match_by_fingerprint "$incoming_fp" 2>/dev/null); then
        :
    else
        best_match=""
    fi

    if [[ -z "$best_match" ]]; then
        append_record "$incoming_record" "$target_store"
        IMPORT_CREATED=$((IMPORT_CREATED + 1))
        return 0
    fi

    local existing_store existing_record existing_fp
    existing_store=$(printf '%s' "$best_match" | jq -r '.store_path')
    existing_record=$(printf '%s' "$best_match" | jq -c '.record')
    existing_fp=$(canonical_fingerprint "$existing_record")

    if [[ "$existing_fp" == "$incoming_fp" ]]; then
        local merged
        merged=$(merge_duplicate_records "$existing_record" "$incoming_record")
        if ! wisdom_validate_canonical "$merged" >/dev/null 2>&1; then
            log_error "Merged duplicate failed canonical validation for manifest: $manifest_file"
            return 1
        fi
        if [[ "$merged" != "$existing_record" ]]; then
            update_record "$merged" "$existing_store"
            IMPORT_MERGED=$((IMPORT_MERGED + 1))
        else
            IMPORT_SKIPPED=$((IMPORT_SKIPPED + 1))
        fi
        return 0
    fi

    local new_id replacement_record existing_id superseded_record
    new_id=$(wisdom_generate_id)
    replacement_record=$(printf '%s' "$incoming_record" | jq -c \
        --arg new_id "$new_id" \
        --argjson existing "$existing_record" '
        .id = $new_id
        | .tags = ((.tags // []) + ($existing.tags // []) | map(select(type == "string") | ascii_downcase) | unique)
    ')
    replacement_record=$(wisdom_normalize_record "$replacement_record")

    if ! wisdom_validate_canonical "$replacement_record" >/dev/null 2>&1; then
        log_error "Replacement record failed canonical validation for manifest: $manifest_file"
        return 1
    fi

    append_record "$replacement_record" "$existing_store"

    existing_id=$(printf '%s' "$existing_record" | jq -r '.id')
    superseded_record=$(printf '%s' "$existing_record" | jq -c --arg new_id "$new_id" '
        .status = "superseded"
        | .superseded_by = $new_id
    ')
    superseded_record=$(wisdom_normalize_record "$superseded_record")

    if ! wisdom_validate_canonical "$superseded_record" >/dev/null 2>&1; then
        log_error "Superseded record failed canonical validation for existing id: $existing_id"
        return 1
    fi

    wisdom_update_entry "$existing_id" "$existing_store" "$superseded_record"
    IMPORT_REPLACED=$((IMPORT_REPLACED + 1))
}

import_phase() {
    [[ -d "$MANIFEST_ROOT" ]] || {
        log_warn "Manifest root not found, skipping import phase: $MANIFEST_ROOT"
        return 0
    }

    local imported_any=0
    local manifest_file
    while IFS= read -r manifest_file; do
        [[ -f "$manifest_file" ]] || continue
        import_one_manifest "$manifest_file"
        imported_any=1
    done < <(find "$MANIFEST_ROOT" -type f -name '*.md' | sort)

    if [[ "$imported_any" -eq 0 ]]; then
        log_warn "No manifest files found under $MANIFEST_ROOT"
    fi

    log_info "Import completed: created=$IMPORT_CREATED merged=$IMPORT_MERGED replaced=$IMPORT_REPLACED skipped=$IMPORT_SKIPPED"
}

main() {
    local do_backup=1
    local do_normalize=1
    local do_import=1
    local restore_tarball=""
    local restore_target="/"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --skip-backup)
                do_backup=0
                shift
                ;;
            --backup-only)
                do_backup=1
                do_normalize=0
                do_import=0
                shift
                ;;
            --normalize-only)
                do_backup=0
                do_normalize=1
                do_import=0
                shift
                ;;
            --import-only)
                do_backup=0
                do_normalize=0
                do_import=1
                shift
                ;;
            --restore)
                restore_tarball="${2:-}"
                if [[ -z "$restore_tarball" ]]; then
                    log_error "--restore requires a tarball path"
                    exit 2
                fi
                shift 2
                ;;
            --restore-target)
                restore_target="${2:-}"
                if [[ -z "$restore_target" ]]; then
                    log_error "--restore-target requires a directory path"
                    exit 2
                fi
                shift 2
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 2
                ;;
        esac
    done

    choose_primary_wisdom_root

    if [[ -n "$restore_tarball" ]]; then
        restore_phase "$restore_tarball" "$restore_target"
        exit 0
    fi

    if [[ "$do_backup" -eq 1 ]]; then
        backup_phase
    fi

    if [[ "$do_normalize" -eq 1 ]]; then
        normalize_phase
    fi

    if [[ "$do_import" -eq 1 ]]; then
        import_phase
    fi

    log_info "Migration complete"
    if [[ -n "$LAST_BACKUP_TARBALL" ]]; then
        printf 'backup=%s\n' "$LAST_BACKUP_TARBALL"
    fi
    printf 'normalized_files=%d normalized_records=%d import_created=%d import_merged=%d import_replaced=%d import_skipped=%d\n' \
        "$NORMALIZED_FILES" "$NORMALIZED_RECORDS" "$IMPORT_CREATED" "$IMPORT_MERGED" "$IMPORT_REPLACED" "$IMPORT_SKIPPED"
}

main "$@"
