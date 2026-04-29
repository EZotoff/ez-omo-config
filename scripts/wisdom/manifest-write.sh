#!/usr/bin/env bash
set -euo pipefail

# manifest-write.sh — Create a new knowledge manifest with YAML frontmatter + markdown body
# Usage: manifest-write.sh --title "..." --type <type> --scope <scope> --owner "..." --body "..." [OPTIONS]

SCRIPT_DIR="$(dirname "$0")"
source "${SCRIPT_DIR}/knowledge-constants.sh"

# === Valid Enums ===
VALID_TYPES=(deployment topology env-caveat runbook provider-gotcha conventions cross-repo preferences anti-pattern ownership observability rollout-state)
VALID_SCOPES=(system workspace project)
VALID_SENSITIVITIES=(public internal restricted)

# === Defaults ===
TITLE=""
TYPE=""
SCOPE=""
OWNER=""
BODY=""
VALIDATION_METHOD=""
FRESHNESS_DAYS=90
SENSITIVITY="internal"
TAGS=""

# === Usage ===
usage() {
    cat >&2 <<'EOF'
Usage: manifest-write.sh [OPTIONS]

Required:
  --title TEXT              Human-readable title
  --type TYPE               Manifest type (deployment|topology|env-caveat|runbook|
                            provider-gotcha|conventions|cross-repo|preferences|
                            anti-pattern|ownership|observability|rollout-state)
  --scope SCOPE             system|workspace|project
  --owner TEXT              Who maintains this manifest
  --body TEXT               Markdown body content (reads stdin if omitted)
  --tags TEXT               Comma-separated tags

Optional:
  --validation-method TEXT  How to verify this knowledge
  --freshness-days N        Days until review is due (default: 90)
  --sensitivity LEVEL       public|internal|restricted (default: internal)
  --help, -h               Show this help

Output:
  Prints the generated manifest ID (UUID) to stdout.
  Writes manifest file to ~/.sisyphus/knowledge/manifests/{scope}/{slug}.md

Exit codes:
  0  Manifest written successfully
  1  General error
  2  Bad arguments / missing required fields
EOF
    exit 2
}

# === Logging ===
log() {
    local level="$1"; shift
    printf '[manifest-write] %s: %s\n' "$level" "$*" >&2
}

# === Parse Arguments ===
while [[ $# -gt 0 ]]; do
    case "$1" in
        --title)
            [[ $# -lt 2 ]] && { log ERROR "--title requires a value"; usage; }
            TITLE="$2"; shift 2 ;;
        --type)
            [[ $# -lt 2 ]] && { log ERROR "--type requires a value"; usage; }
            TYPE="$2"; shift 2 ;;
        --scope)
            [[ $# -lt 2 ]] && { log ERROR "--scope requires a value"; usage; }
            SCOPE="$2"; shift 2 ;;
        --owner)
            [[ $# -lt 2 ]] && { log ERROR "--owner requires a value"; usage; }
            OWNER="$2"; shift 2 ;;
        --body)
            [[ $# -lt 2 ]] && { log ERROR "--body requires a value"; usage; }
            BODY="$2"; shift 2 ;;
        --validation-method)
            [[ $# -lt 2 ]] && { log ERROR "--validation-method requires a value"; usage; }
            VALIDATION_METHOD="$2"; shift 2 ;;
        --freshness-days)
            [[ $# -lt 2 ]] && { log ERROR "--freshness-days requires a value"; usage; }
            FRESHNESS_DAYS="$2"; shift 2 ;;
        --sensitivity)
            [[ $# -lt 2 ]] && { log ERROR "--sensitivity requires a value"; usage; }
            SENSITIVITY="$2"; shift 2 ;;
        --tags)
            [[ $# -lt 2 ]] && { log ERROR "--tags requires a value"; usage; }
            TAGS="$2"; shift 2 ;;
        --help|-h)
            usage ;;
        *)
            log ERROR "Unknown option: $1"
            usage ;;
    esac
done

# === Read body from stdin if not provided ===
if [[ -z "$BODY" ]]; then
    BODY=$(cat)
fi

# === Validate Required Fields ===
missing=()
[[ -z "$TITLE" ]] && missing+=("--title")
[[ -z "$TYPE" ]] && missing+=("--type")
[[ -z "$SCOPE" ]] && missing+=("--scope")
[[ -z "$OWNER" ]] && missing+=("--owner")
[[ -z "$BODY" ]] && missing+=("--body")
[[ -z "$TAGS" ]] && missing+=("--tags")

if [[ ${#missing[@]} -gt 0 ]]; then
    log ERROR "Missing required fields: ${missing[*]}"
    usage
fi

# === Validate Enums ===
_validate_enum() {
    local value="$1"; shift
    local name="$1"; shift
    local valid=("$@")
    local found=false
    for v in "${valid[@]}"; do
        if [[ "$value" == "$v" ]]; then
            found=true
            break
        fi
    done
    if [[ "$found" == false ]]; then
        log ERROR "Invalid ${name}: '${value}' (valid: ${valid[*]})"
        exit 2
    fi
}

_validate_enum "$TYPE" "type" "${VALID_TYPES[@]}"
_validate_enum "$SCOPE" "scope" "${VALID_SCOPES[@]}"
_validate_enum "$SENSITIVITY" "sensitivity" "${VALID_SENSITIVITIES[@]}"

# === Validate freshness-days is a positive integer ===
if ! [[ "$FRESHNESS_DAYS" =~ ^[0-9]+$ ]] || [[ "$FRESHNESS_DAYS" -eq 0 ]]; then
    log ERROR "--freshness-days must be a positive integer"
    exit 2
fi

# === Generate ID and Dates ===
MANIFEST_ID=$(uuidgen)
NOW_ISO=$(date -u +%Y-%m-%dT%H:%M:%SZ)
REVIEW_DUE=$(date -u -d "+${FRESHNESS_DAYS} days" +%Y-%m-%dT%H:%M:%SZ)

# === Compute Slug from Title ===
# Lowercase, replace spaces/non-alphanumeric with dashes, collapse multiple dashes, trim trailing
SLUG=$(printf '%s' "$TITLE" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g; s/--*/-/g; s/^-//; s/-$//')

if [[ -z "$SLUG" ]]; then
    log ERROR "Could not generate slug from title: '${TITLE}'"
    exit 1
fi

# === Determine Output Directory ===
case "$SCOPE" in
    system)    OUTPUT_DIR="${KNOWLEDGE_SYSTEM_DIR}" ;;
    workspace) OUTPUT_DIR="${KNOWLEDGE_WORKSPACE_DIR}" ;;
    project)   OUTPUT_DIR="${KNOWLEDGE_PROJECT_DIR}" ;;
esac

# Ensure directory exists
mkdir -p "$OUTPUT_DIR"

OUTPUT_FILE="${OUTPUT_DIR}/${SLUG}.md"

# Check for existing file
if [[ -f "$OUTPUT_FILE" ]]; then
    log ERROR "Manifest file already exists: ${OUTPUT_FILE}"
    log ERROR "Use a different title or remove the existing file first"
    exit 1
fi

# === Format Tags as YAML List ===
TAGS_YAML=""
IFS=',' read -ra TAG_ARRAY <<< "$TAGS"
for tag in "${TAG_ARRAY[@]}"; do
    tag=$(printf '%s' "$tag" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if [[ -n "$tag" ]]; then
        TAGS_YAML="${TAGS_YAML}, ${tag}"
    fi
done
TAGS_YAML="[${TAGS_YAML:2}]"

# === Build Validation Method Line ===
VALIDATION_LINE=""
if [[ -n "$VALIDATION_METHOD" ]]; then
    VALIDATION_LINE="validation_method: \"${VALIDATION_METHOD}\""
else
    VALIDATION_LINE="validation_method: null"
fi

# === Write Manifest File ===
cat > "$OUTPUT_FILE" <<MANIFEST
---
id: ${MANIFEST_ID}
title: "${TITLE}"
type: ${TYPE}
scope: ${SCOPE}
owner: "${OWNER}"
provenance: manual
${VALIDATION_LINE}
last_verified: "${NOW_ISO}"
freshness_days: ${FRESHNESS_DAYS}
review_due: "${REVIEW_DUE}"
sensitivity: ${SENSITIVITY}
status: verified
superseded_by: null
tags: ${TAGS_YAML}
---

${BODY}
MANIFEST

# === Verify Write ===
if [[ ! -f "$OUTPUT_FILE" ]]; then
    log ERROR "Failed to write manifest file: ${OUTPUT_FILE}"
    exit 1
fi

log INFO "Manifest written: ${OUTPUT_FILE}"
printf '%s\n' "$MANIFEST_ID"
exit 0
