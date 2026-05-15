#!/usr/bin/env bash
set -euo pipefail

# wisdom-observe.sh — Operator-facing observability CLI for Wisdom events
# Usage: wisdom-observe.sh <subcommand> [options]

# Source shared library
source "$(dirname "$0")/wisdom-common.sh"
wisdom_init_observability "$(basename "$0")"
wisdom_require_jq

# --------------------------------------------------------------------------
# Defaults
# --------------------------------------------------------------------------
SUBCOMMAND=""
LIMIT=""
EVENT_FILTER=""
STATUS_FILTER=""
JSON_OUTPUT=false
TRACE_ID_ARG=""
RESET_YES=false

# --------------------------------------------------------------------------
# Usage
# --------------------------------------------------------------------------
usage() {
    cat >&2 <<'EOF'
Usage: wisdom-observe.sh <subcommand> [options]

Subcommands:
  status              Print event file status and metadata
  read [options]      Read events with optional filtering
  trace TRACE_ID      Print all events for a trace ID
  reset --yes         Truncate the events file (requires --yes)

read options:
  --limit N           Limit to N most recent events
  --event EVENT       Filter by event name
  --status STATUS     Filter by status
  --json              Output as JSON array

trace options:
  --json              Output as JSON array

reset options:
  --yes               Confirm truncation (required)

Exit codes:
  0  Success
  1  No events found or file missing
  2  Bad arguments
EOF
    exit 2
}

# --------------------------------------------------------------------------
# status subcommand
# --------------------------------------------------------------------------
cmd_status() {
    local event_file
    event_file=$(wisdom_events_path)

    local exists="no"
    local line_count=0
    local newest_ts=""
    local oldest_ts=""
    local enabled="yes"

    if [[ "${WISDOM_OBSERVABILITY:-1}" == "0" ]]; then
        enabled="no"
    fi

    if [[ -f "$event_file" ]]; then
        exists="yes"
        line_count=$(wc -l < "$event_file" | tr -d ' ')
        if [[ "$line_count" -gt 0 ]]; then
            newest_ts=$(tail -n 1 "$event_file" | jq -r '.ts // ""')
            oldest_ts=$(head -n 1 "$event_file" | jq -r '.ts // ""')
        fi
    fi

    printf 'event_path:      %s\n' "$event_file"
    printf 'exists:          %s\n' "$exists"
    printf 'line_count:      %d\n' "$line_count"
    printf 'newest_ts:       %s\n' "${newest_ts:-(none)}"
    printf 'oldest_ts:       %s\n' "${oldest_ts:-(none)}"
    printf 'retention_limit: %d\n' "$WISDOM_EVENTS_MAX_LINES"
    printf 'observability:   %s\n' "$enabled"
}

# --------------------------------------------------------------------------
# read subcommand
# --------------------------------------------------------------------------
cmd_read() {
    local event_file
    event_file=$(wisdom_events_path)

    if [[ ! -f "$event_file" ]]; then
        if [[ "$JSON_OUTPUT" == true ]]; then
            echo "[]"
        else
            echo "No events file found."
        fi
        exit 1
    fi

    local events
    events=$(wisdom_read_events "${LIMIT:-}")

    if [[ -z "$events" ]]; then
        if [[ "$JSON_OUTPUT" == true ]]; then
            echo "[]"
        else
            echo "No events found."
        fi
        exit 1
    fi

    # Apply filters
    if [[ -n "$EVENT_FILTER" ]]; then
        events=$(printf '%s\n' "$events" | jq -c --arg ev "$EVENT_FILTER" 'select(.event == $ev)' 2>/dev/null)
    fi

    if [[ -n "$STATUS_FILTER" ]]; then
        events=$(printf '%s\n' "$events" | jq -c --arg st "$STATUS_FILTER" 'select(.status == $st)' 2>/dev/null)
    fi

    if [[ -z "$events" ]]; then
        if [[ "$JSON_OUTPUT" == true ]]; then
            echo "[]"
        else
            echo "No events matched filters."
        fi
        exit 1
    fi

    if [[ "$JSON_OUTPUT" == true ]]; then
        printf '%s\n' "$events" | jq -s '.'
    else
        printf '%s\n' "$events" | while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            local ts ev st trid
            ts=$(printf '%s' "$line" | jq -r '.ts // "-"')
            ev=$(printf '%s' "$line" | jq -r '.event // "-"')
            st=$(printf '%s' "$line" | jq -r '.status // "-"')
            trid=$(printf '%s' "$line" | jq -r '.trace_id // "-"')
            printf '%s | %s | %s | %s\n' "$ts" "$ev" "$st" "$trid"
        done
    fi
}

# --------------------------------------------------------------------------
# trace subcommand
# --------------------------------------------------------------------------
cmd_trace() {
    if [[ -z "$TRACE_ID_ARG" ]]; then
        wisdom_log ERROR "trace requires a TRACE_ID argument"
        usage
    fi

    local event_file
    event_file=$(wisdom_events_path)

    if [[ ! -f "$event_file" ]]; then
        if [[ "$JSON_OUTPUT" == true ]]; then
            echo "[]"
        else
            echo "No events file found."
        fi
        exit 1
    fi

    local events
    events=$(jq -c --arg tid "$TRACE_ID_ARG" 'select(.trace_id == $tid)' "$event_file" 2>/dev/null | sort -t'"' -k4,4)

    if [[ -z "$events" ]]; then
        if [[ "$JSON_OUTPUT" == true ]]; then
            echo "[]"
        else
            echo "No events found for trace_id: $TRACE_ID_ARG"
        fi
        exit 1
    fi

    if [[ "$JSON_OUTPUT" == true ]]; then
        printf '%s\n' "$events" | jq -s '.'
    else
        printf '%s\n' "$events" | while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            local ts ev st inv
            ts=$(printf '%s' "$line" | jq -r '.ts // "-"')
            ev=$(printf '%s' "$line" | jq -r '.event // "-"')
            st=$(printf '%s' "$line" | jq -r '.status // "-"')
            inv=$(printf '%s' "$line" | jq -r '.invocation_id // "-"')
            printf '%s | %s | %s | %s\n' "$ts" "$ev" "$st" "$inv"
        done
    fi
}

# --------------------------------------------------------------------------
# reset subcommand
# --------------------------------------------------------------------------
cmd_reset() {
    if [[ "$RESET_YES" != true ]]; then
        cat >&2 <<'EOF'
Error: reset requires --yes flag to confirm truncation.

Usage: wisdom-observe.sh reset --yes
EOF
        exit 2
    fi

    wisdom_reset_events
    echo "Events file reset."
}

# --------------------------------------------------------------------------
# Parse subcommand and arguments
# --------------------------------------------------------------------------
if [[ $# -eq 0 ]]; then
    usage
fi

SUBCOMMAND="$1"
shift

# Parse options after subcommand
case "$SUBCOMMAND" in
    status)
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --help|-h) usage ;;
                *) wisdom_log ERROR "Unknown option for status: $1"; usage ;;
            esac
        done
        cmd_status
        ;;
    read)
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --limit)
                    [[ $# -lt 2 ]] && { wisdom_log ERROR "--limit requires a value"; usage; }
                    LIMIT="$2"; shift 2 ;;
                --event)
                    [[ $# -lt 2 ]] && { wisdom_log ERROR "--event requires a value"; usage; }
                    EVENT_FILTER="$2"; shift 2 ;;
                --status)
                    [[ $# -lt 2 ]] && { wisdom_log ERROR "--status requires a value"; usage; }
                    STATUS_FILTER="$2"; shift 2 ;;
                --json)
                    JSON_OUTPUT=true; shift ;;
                --help|-h)
                    usage ;;
                -*)
                    wisdom_log ERROR "Unknown option for read: $1"; usage ;;
                *)
                    wisdom_log ERROR "Unexpected argument for read: $1"; usage ;;
            esac
        done
        cmd_read
        ;;
    trace)
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --json)
                    JSON_OUTPUT=true; shift ;;
                --help|-h)
                    usage ;;
                -*)
                    wisdom_log ERROR "Unknown option for trace: $1"; usage ;;
                *)
                    if [[ -z "$TRACE_ID_ARG" ]]; then
                        TRACE_ID_ARG="$1"; shift
                    else
                        wisdom_log ERROR "Unexpected argument for trace: $1"; usage
                    fi
                    ;;
            esac
        done
        cmd_trace
        ;;
    reset)
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --yes)
                    RESET_YES=true; shift ;;
                --help|-h)
                    usage ;;
                -*)
                    wisdom_log ERROR "Unknown option for reset: $1"; usage ;;
                *)
                    wisdom_log ERROR "Unexpected argument for reset: $1"; usage ;;
            esac
        done
        cmd_reset
        ;;
    --help|-h)
        usage
        ;;
    *)
        wisdom_log ERROR "Unknown subcommand: $SUBCOMMAND"
        usage
        ;;
esac

exit 0
