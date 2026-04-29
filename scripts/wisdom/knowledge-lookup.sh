#!/usr/bin/env bash
set -euo pipefail

# knowledge-lookup.sh — DEPRECATED compatibility shim
# Reads ONLY from canonical Wisdom store. Never reads manifests.
# Usage: knowledge-lookup.sh <query> [--scope <scope>] [--type <type>] [--authority-min <level>]
#
# DEPRECATION: This script is a backward-compatible shim. New code should call
# wisdom-search.sh directly for canonical Wisdom queries.

SCRIPT_DIR="$(dirname "$0")"
source "${SCRIPT_DIR}/knowledge-constants.sh"
source "${SCRIPT_DIR}/wisdom-common.sh"

# --------------------------------------------------------------------------
# Deprecation warning
# --------------------------------------------------------------------------
printf '[DEPRECATION] knowledge-lookup.sh is deprecated; use wisdom-search.sh directly\n' >&2

# --------------------------------------------------------------------------
# Defaults
# --------------------------------------------------------------------------
QUERY=""
SCOPE=""
TYPE=""
AUTHORITY_MIN=""

# --------------------------------------------------------------------------
# Usage
# --------------------------------------------------------------------------
usage() {
    cat >&2 <<'EOF'
Usage: knowledge-lookup.sh QUERY [OPTIONS]

Search operational knowledge with authority-first ordering.
Reads ONLY from canonical Wisdom store (~/.sisyphus/wisdom/*.jsonl).

Arguments:
  QUERY                    Search string (required, case-insensitive)

Options:
  --scope SCOPE            Filter by scope: system|workspace|project
  --type TYPE              Filter by type (passed to underlying search tools)
  --authority-min LEVEL    Minimum authority level: manifest|verified|wisdom
                            manifest  = only published wisdom
                            verified  = verified + published wisdom
                            wisdom    = everything (default)
  --help, -h               Show this help

Output:
  Structured, agent-parseable results grouped by source with authority annotations.
  Outputs explicit UNKNOWN signal when no results found.

Exit codes:
  0  Found results
  1  No results found (UNKNOWN)
  2  Bad arguments
EOF
    exit 2
}

# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------
log() {
    local level="$1"; shift
    printf '[knowledge-lookup] %s: %s\n' "$level" "$*" >&2
}

# --------------------------------------------------------------------------
# Parse arguments
# --------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --scope)
            [[ $# -lt 2 ]] && { log ERROR "--scope requires a value"; usage; }
            SCOPE="$2"; shift 2 ;;
        --type)
            [[ $# -lt 2 ]] && { log ERROR "--type requires a value"; usage; }
            TYPE="$2"; shift 2 ;;
        --authority-min)
            [[ $# -lt 2 ]] && { log ERROR "--authority-min requires a value"; usage; }
            AUTHORITY_MIN="$2"; shift 2 ;;
        --help|-h)
            usage ;;
        -*)
            log ERROR "Unknown option: $1"
            usage ;;
        *)
            if [[ -z "$QUERY" ]]; then
                QUERY="$1"; shift
            else
                log ERROR "Unexpected argument: $1"
                usage
            fi
            ;;
    esac
done

# QUERY is required
if [[ -z "$QUERY" ]]; then
    log ERROR "QUERY is required"
    usage
fi

# Validate --scope
if [[ -n "$SCOPE" ]]; then
    case "$SCOPE" in
        system|workspace|project) ;;
        *) log ERROR "Invalid scope: $SCOPE (valid: system, workspace, project)"; exit 2 ;;
    esac
fi

# Validate --authority-min
if [[ -n "$AUTHORITY_MIN" ]]; then
    case "$AUTHORITY_MIN" in
        manifest|verified|wisdom) ;;
        *) log ERROR "Invalid authority-min: $AUTHORITY_MIN (valid: manifest, verified, wisdom)"; exit 2 ;;
    esac
fi

min_rank=$(wisdom_authority_rank "${AUTHORITY_MIN:-wisdom}")
if [[ -z "$AUTHORITY_MIN" || "$AUTHORITY_MIN" == "wisdom" ]]; then
    min_rank=0
fi

# --------------------------------------------------------------------------
# Delegate to wisdom-search.sh (canonical)
# --------------------------------------------------------------------------
wisdom_args=("$QUERY" --json --limit 20)

# Map scope for wisdom-search (it uses system|project|plan|all)
if [[ -n "$SCOPE" ]]; then
    case "$SCOPE" in
        system)    wisdom_args+=(--scope system) ;;
        project)   wisdom_args+=(--scope project) ;;
        workspace) ;; # wisdom has no workspace scope, search all
    esac
fi

[[ -n "$TYPE" ]] && wisdom_args+=(--type "$TYPE")

# Capture wisdom-search JSON output (suppress stderr)
wisdom_raw=""
wisdom_raw=$("${SCRIPT_DIR}/wisdom-search.sh" "${wisdom_args[@]}" 2>/dev/null) || true

wisdom_count=0
wisdom_verified_count=0
wisdom_candidate_count=0
wisdom_output=""

if [[ -n "$wisdom_raw" && "$wisdom_raw" != "[]" && "$wisdom_raw" != '"UNKNOWN"' ]]; then
    if command -v jq &>/dev/null; then
        filtered=$(printf '%s' "$wisdom_raw" | jq --argjson min_rank "$min_rank" '
            [ .[] | select((.authority // "candidate") as $a |
                if $a == "published" then 3
                elif $a == "verified" then 2
                elif $a == "candidate" then 1
                else 0 end >= $min_rank
            ) ]
        ')

        wisdom_count=$(printf '%s' "$filtered" | jq 'length')

        if [[ "$wisdom_count" -gt 0 ]]; then
            for i in $(seq 0 $((wisdom_count - 1))); do
                entry=$(printf '%s' "$filtered" | jq -c ".[$i]")

                w_id=$(printf '%s' "$entry" | jq -r '.id')
                w_body=$(printf '%s' "$entry" | jq -r '.body // ""')
                w_authority=$(printf '%s' "$entry" | jq -r '.authority // "candidate"')
                w_provenance=$(printf '%s' "$entry" | jq -r '.provenance // "unknown"')
                w_created=$(printf '%s' "$entry" | jq -r '.created // .timestamp // "unknown"')
                w_type=$(printf '%s' "$entry" | jq -r '.type // "unknown"')
                w_status=$(printf '%s' "$entry" | jq -r '.status // "unknown"')
                w_verified_at=$(printf '%s' "$entry" | jq -r '.verified_at // "unknown"')

                case "$w_authority" in
                    published|verified) annotation="VERIFIED" ;;
                    *) annotation="CANDIDATE" ;;
                esac

                if [[ "$annotation" == "VERIFIED" ]]; then
                    ((wisdom_verified_count++)) || true
                else
                    ((wisdom_candidate_count++)) || true
                fi

                if [[ ${#w_body} -gt 200 ]]; then
                    w_body="${w_body:0:200}..."
                fi

                wisdom_output+="[${annotation}] id:${w_id} — \"${w_body%%$'\n'*}\""$'\n'
                first_line="${w_body%%$'\n'*}" 
                if [[ "$w_body" != "$first_line" ]]; then
                    wisdom_output+="  ${w_body}"$'\n'
                fi
                wisdom_output+="  (source: ${w_provenance}, type: ${w_type}, status: ${w_status}, captured: ${w_created})"$'\n'
                if [[ "$w_verified_at" != "unknown" && "$w_verified_at" != "null" ]]; then
                    wisdom_output+="  (verified_at: ${w_verified_at})"$'\n'
                fi
                wisdom_output+=""$'\n'
            done
        fi
    else
        log WARN "jq not available — cannot parse wisdom results"
    fi
fi

# --------------------------------------------------------------------------
# Output Results
# --------------------------------------------------------------------------
total_count=$wisdom_count

printf '## Results for: "%s"\n\n' "$QUERY"

if [[ $total_count -eq 0 ]]; then
    printf '### UNKNOWN\n'
    printf 'No documented knowledge found for this query.\n'
    printf 'This topic is undocumented — do NOT infer from code.\n'
    printf 'Answer with: "This is unknown/undocumented"\n'
    exit 1
fi

# Wisdom (Canonical) section
if [[ $wisdom_count -gt 0 ]]; then
    printf '### Wisdom (Canonical)\n'
    printf '%s' "$wisdom_output"
fi

printf '### Authority Summary\n'
summary_parts=()
if [[ $wisdom_verified_count -gt 0 ]]; then
    summary_parts+=("${wisdom_verified_count} verified")
fi
if [[ $wisdom_candidate_count -gt 0 ]]; then
    summary_parts+=("${wisdom_candidate_count} candidate")
fi

printf 'Found: %s\n' "$(IFS=', '; printf '%s' "${summary_parts[*]}")"

exit 0
