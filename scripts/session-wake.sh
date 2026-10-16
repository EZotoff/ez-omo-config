#!/usr/bin/env bash
# session-wake.sh — durable scheduled wake-up prompts for OpenCode agent sessions.
#
# WHY: turn-based agents have no clock. The 30-min inactivity window kills
# background-subagent watchers on long horizons, and "I'll check tomorrow" from
# an ending turn is a promise that never fires (AGENTS.md: no unbound promises).
# This utility arms a SYSTEMD TRANSIENT TIMER (survives the session's turn end,
# independent of the opencode servers) that POSTs a wake-up prompt into a target
# session via /session/:id/prompt_async at a scheduled absolute time.
#
# Usage:
#   session-wake.sh arm --session ses_x --at '2026-10-17 15:15:00 CEST' \
#       --server http://127.0.0.1:3030 --prompt-file /path/prompt.md \
#       [--unit wake-<purpose>-<YYYYMMDD>] [--precondition /path/marker]
#   session-wake.sh fire --session ses_x --server http://... --prompt-file <state-copy> \
#       [--precondition /path/marker] [--unit NAME]     (invoked by the timer)
#   session-wake.sh cancel --unit wake-<purpose>-<date>
#   session-wake.sh list
#
# Contract (docs/rollout-protocol.md §10 "Scheduled session wakes"; Oracle
# design 2026-10-16): DISJOINT from the OMO wake-journal state machine — shared
# pattern (atomic claims, terminal-event accounting), not shared state.
#   - Terminal events: delivered | fire-failed | suppressed-precondition |
#     cancelled | missed (sweep-asserted). A wake with `armed` and no terminal
#     event >24h past `at` is an incident, not silence.
#   - Fire takes an O_EXCL claim (`.claim-<unit>`, noclobber) BEFORE the POST —
#     double arms/racers log dup-suppressed (lesson: the 12-identical-nudge
#     bursts came from a check-then-write race).
#   - --precondition FILE: if the file EXISTS at fire time the condition already
#     resolved — self-cancel with suppressed-precondition, no POST.
#   - The prompt is COPIED into WAKE_DIR at arm; fire reads the copy (the
#     original path may be gone hours/days later).
#   - Prompt content rules: self-identifying header, exact action, durable-state
#     reconciliation instructions; woken agent reconciles from state, not memory.
#   - Reboot class: transient (default; a reboot before fire drops the timer —
#     the post-boot sweep stamps `missed`). Reboot-critical wakes need an
#     installed timer instead.
#
# State/audit: ~/.local/share/opencode/session-wakes/ (wakes.jsonl + per-unit
# prompt copies + claim markers).

set -euo pipefail

WAKE_DIR="${XDG_STATE_DIR:-$HOME/.local/share/opencode}/session-wakes"
WAKE_LOG="$WAKE_DIR/wakes.jsonl"

server_password() { # <server-url> — from the unit env file matching the port; NEVER on a command line
  local port="${1##*:}"
  case "$port" in
    3030) env_file="$HOME/.config/opencode/serve-interactive.env" ;;
    3040) env_file="$HOME/.config/opencode/serve-bench.env" ;;
    *)    env_file="$HOME/.config/opencode/serve.env" ;;
  esac
  grep '^OPENCODE_SERVER_PASSWORD=' "$env_file" | cut -d= -f2-
}

cmd="${1:-}"; shift || true
SESSION=""; AT=""; SERVER=""; PROMPT_FILE=""; UNIT=""; PRECONDITION=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --session) SESSION="$2"; shift 2 ;;
    --at) AT="$2"; shift 2 ;;
    --server) SERVER="$2"; shift 2 ;;
    --prompt-file) PROMPT_FILE="$2"; shift 2 ;;
    --unit) UNIT="$2"; shift 2 ;;
    --precondition) PRECONDITION="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

log_wake() { # <event> <details-json>
  mkdir -p "$WAKE_DIR"
  printf '{"ts":"%s","event":"%s",%s}\n' "$(date +%Y-%m-%dT%H:%M:%S%z)" "$1" "$2" >> "$WAKE_LOG"
}

case "$cmd" in
  arm)
    [[ -n "$SESSION" && -n "$AT" && -n "$SERVER" && -n "$PROMPT_FILE" ]] || { echo "arm needs --session --at --server --prompt-file" >&2; exit 2; }
    [[ -r "$PROMPT_FILE" ]] || { echo "prompt file unreadable: $PROMPT_FILE" >&2; exit 2; }
    UNIT="${UNIT:-wake-$(basename "$PROMPT_FILE" .md)-$(date +%Y%m%d%H%M%S)}"
    # Own the prompt bytes: fire reads the state-dir copy, not the original path.
    STATE_PROMPT="$WAKE_DIR/$UNIT.prompt.md"
    mkdir -p "$WAKE_DIR"
    cp "$PROMPT_FILE" "$STATE_PROMPT"
    systemd-run --user --unit="$UNIT" --on-calendar="$AT" \
      "$HOME/ez-omo-config/scripts/session-wake.sh" fire \
      --session "$SESSION" --server "$SERVER" --prompt-file "$STATE_PROMPT" \
      --unit "$UNIT" ${PRECONDITION:+--precondition "$PRECONDITION"}
    log_wake armed "\"unit\":\"$UNIT\",\"session\":\"$SESSION\",\"at\":\"$AT\",\"server\":\"$SERVER\",\"reboot_class\":\"transient\"${PRECONDITION:+,\"precondition\":\"$PRECONDITION\"}"
    echo "armed: $UNIT fires at $AT -> $SESSION on $SERVER (prompt: $STATE_PROMPT)"
    ;;
  fire)
    [[ -n "$SESSION" && -n "$SERVER" && -n "$PROMPT_FILE" ]] || { echo "fire needs --session --server --prompt-file" >&2; exit 2; }
    UNIT="${UNIT:-fire-manual}"
    # Precondition self-cancel: the condition already resolved — do not nudge.
    if [[ -n "$PRECONDITION" && -e "$PRECONDITION" ]]; then
      log_wake suppressed-precondition "\"unit\":\"$UNIT\",\"precondition\":\"$PRECONDITION\""
      echo "suppressed: precondition $PRECONDITION exists (condition already resolved)"
      exit 0
    fi
    # Exactly-one-fire claim: O_EXCL-equivalent (noclobber) BEFORE the POST.
    CLAIM="$WAKE_DIR/.claim-$UNIT"
    mkdir -p "$WAKE_DIR"
    if ! ( set -o noclobber; : > "$CLAIM" ) 2>/dev/null; then
      log_wake dup-suppressed "\"unit\":\"$UNIT\""
      echo "dup-suppressed: claim $CLAIM already exists" >&2
      exit 0
    fi
    printf '%s\n' "$(date +%Y-%m-%dT%H:%M:%S%z)" > "$CLAIM"
    PASS="$(server_password "$SERVER")"
    [[ -n "$PASS" ]] || { log_wake fire-failed "\"unit\":\"$UNIT\",\"reason\":\"no-password\""; echo "no password for $SERVER" >&2; exit 1; }
    [[ -r "$PROMPT_FILE" ]] || { log_wake fire-failed "\"unit\":\"$UNIT\",\"reason\":\"prompt-copy-gone\""; echo "prompt copy unreadable: $PROMPT_FILE" >&2; exit 1; }
    # Server may be mid-recycle (recycles take ~30s): retry every 10s up to 5 min.
    TEXT="$(cat "$PROMPT_FILE")"
    BODY="$(python3 -c 'import json,sys; print(json.dumps({"parts":[{"type":"text","text":sys.stdin.read(),"synthetic":True}]}))' <<< "$TEXT")"
    for i in $(seq 1 30); do
      if curl -sS -f --connect-timeout 3 --max-time 15 -u "opencode:$PASS" \
           -H 'Content-Type: application/json' -d "$BODY" \
           "$SERVER/session/$SESSION/prompt_async" > /dev/null 2>&1; then
        log_wake delivered "\"unit\":\"$UNIT\",\"session\":\"$SESSION\",\"server\":\"$SERVER\",\"attempt\":$i"
        echo "wake delivered to $SESSION via $SERVER (attempt $i)"
        exit 0
      fi
      sleep 10
    done
    log_wake fire-failed "\"unit\":\"$UNIT\",\"session\":\"$SESSION\",\"server\":\"$SERVER\",\"reason\":\"unreachable-5min\""
    echo "server unreachable for 5 min; wake NOT delivered (see $WAKE_LOG)" >&2
    exit 1
    ;;
  cancel)
    [[ -n "$UNIT" ]] || { echo "cancel needs --unit" >&2; exit 2; }
    systemctl --user stop "$UNIT.timer" 2>/dev/null || true
    systemctl --user stop "$UNIT.service" 2>/dev/null || true
    log_wake cancelled "\"unit\":\"$UNIT\""
    echo "cancelled: $UNIT (timer+service stopped, audit stamped)"
    ;;
  list)
    systemctl --user list-timers --all | grep -E 'wake-|ACTIVATES' || echo "(no wake timers armed)"
    ;;
  *) echo "usage: session-wake.sh arm|fire|cancel|list ..." >&2; exit 2 ;;
esac
