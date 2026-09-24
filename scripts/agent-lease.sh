#!/usr/bin/env bash
#
# agent-lease.sh — budget/lease ledger with checkpoint-handoff semantics (W3.2)
#
# Plan: .omo/plans/workflow-standardization.md §W3 TODO item 12.
#
# Leases live in .omo/leases.jsonl (append-only JSONL, flock-serialized;
# one flock on <leases>.lock). Every mutation appends a new record — records
# are never rewritten. The LAST record for a lease id is its current state.
#
# Lease record: { id, session_id, role, soft_budget_tokens, expires_at (ISO),
#                 budget_messages (nullable int), state: active|expired|released|handed_off,
#                 created_at }
# Handoff record: { handoff: true, lease_id, reason: "budget_exhausted",
#                    action: "checkpoint_handoff", trigger: "time"|"budget", ts }
#
# Semantics: an expired lease NEVER emits kill instructions. The documented
# transition is checkpoint/ledger handoff — the orchestrator (or its scribe)
# consumes the handoff record to snapshot and hand the unit of work to a
# fresh session. Hard-kill is reserved for runaway patterns and is an
# orchestrator decision, not this tool's.
#
# Subcommands:
#   create  --session ses_x --role R --soft-budget N --expires-at ISO
#            [--budget-messages N] [--leases FILE] [--usage-from-db] [--db FILE]
#       Appends an active lease record; prints its JSON. --usage-from-db adds
#       a read-only usage approximation: {message_count, part_count} for the
#       session from opencode.db (sqlite3 mode=ro URI; never written).
#       --budget-messages N records a message-count budget; `check` enforces
#       it when given --usage-from-db (over-budget ACTIVE lease → expired +
#       handoff with trigger: "budget").
#   check   --id LEASE_ID [--leases FILE] [--now ISO]
#           [--usage-from-db] [--db FILE]
#       Prints the current lease record (with any state transition applied).
#       If state==active and now > expires_at → appends an expired record AND
#       a handoff record {lease_id, reason: budget_exhausted,
#       action: checkpoint_handoff, trigger: "time"}. If state==active and
#       --usage-from-db and the session's live message_count exceeds
#       budget_messages → same transition with trigger: "budget".
#       Healing: if the latest state is `expired` but NO handoff record exists
#       for the lease (crash between the two appends), the missing handoff is
#       emitted (idempotent — no duplicates on the normal path).
#   renew   --id LEASE_ID --extend-minutes N [--leases FILE] [--now ISO]
#       Only active leases; expires_at += N minutes (appended record).
#   release --id LEASE_ID [--leases FILE] [--now ISO]
#       Only active leases; state → released.
#
# Timestamps: --expires-at and --now MUST carry an explicit UTC designator
# (trailing Z) or numeric offset (+HH:MM). Naive local-time ISO strings are
# rejected with an error.
#
# Overrides for testability: --leases FILE (default .omo/leases.jsonl),
# --db FILE (default ~/.local/share/opencode/opencode.db).
#
# Exit codes: 0 success; 1 usage/error.
#
# Dependencies: bash >= 4.3, jq, flock, python3 (for --usage-from-db).

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
DEFAULT_LEASES=".omo/leases.jsonl"
DEFAULT_DB="${HOME}/.local/share/opencode/opencode.db"

die() {
    echo "error: $*" >&2
    exit 1
}

now_iso() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# ISO string -> epoch seconds (portable: no date -d on macOS stock).
iso_to_epoch() {
    python3 -c 'import sys,datetime; print(int(datetime.datetime.fromisoformat(sys.argv[1].replace("Z","+00:00")).timestamp()))' "$1"
}

epoch_to_iso() {
    python3 -c 'import sys,datetime; print(datetime.datetime.fromtimestamp(int(sys.argv[1]), datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))' "$1"
}

# Reject naive (timezone-less) ISO strings: require Z or numeric offset.
require_tz() {
    python3 -c 'import sys,datetime; dt=datetime.datetime.fromisoformat(sys.argv[1].replace("Z","+00:00")); sys.exit(0 if dt.tzinfo is not None else 1)' "$1" 2>/dev/null
}

iso_tz_or_die() { # what value -> die with a clear message on naive/invalid ISO
    local what="$1" val="$2"
    iso_to_epoch "$val" >/dev/null 2>&1 || die "$what must be ISO8601 (got: $val)"
    require_tz "$val" || die "$what must include a timezone (trailing Z or +HH:MM offset), e.g. 2030-01-01T00:00:00Z — naive local-time timestamps are ambiguous and rejected (got: $val)"
}

# Read-only usage approximation from opencode.db (mode=ro URI, LIMIT queries).
usage_from_db() {
    local db="$1" sid="$2"
    [[ -f "$db" ]] || die "db not found: $db"
    python3 - "$db" "$sid" <<'PYEOF'
import json, sqlite3, sys
db, sid = sys.argv[1], sys.argv[2]
con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
try:
    mc = con.execute(
        "select count(*) from message where session_id = ? limit 1", (sid,)
    ).fetchone()[0]
    pc = con.execute(
        "select count(*) from part where session_id = ? limit 1", (sid,)
    ).fetchone()[0]
finally:
    con.close()
print(json.dumps({"message_count": mc, "part_count": pc}))
PYEOF
}

acquire_lock() {
    local lf="$1"
    exec 9>"$lf.lock"
    flock 9
}

release_lock() {
    exec 9>&- 2>/dev/null || true
}

# Last record for lease id; empty if none.
last_record_for() {
    local lf="$1" id="$2"
    jq -r --arg id "$id" \
        'select(.id == $id) | tojson' "$lf" 2>/dev/null | tail -n 1
}

# 0 (true) if a handoff record exists for the lease id.
handoff_exists() {
    local lf="$1" id="$2"
    jq -e --arg id "$id" 'select(.handoff == true and .lease_id == $id) | true' "$lf" >/dev/null 2>&1
}

append_handoff() { # lf id trigger ts
    local lf="$1" id="$2" trigger="$3" ts="$4"
    local handoff
    handoff="$(jq -S -c -n --arg lid "$id" --arg trg "$trigger" --arg ts "$ts" \
        '{handoff: true, lease_id: $lid,
          reason: "budget_exhausted", action: "checkpoint_handoff", trigger: $trg, ts: $ts}')"
    append_record "$lf" "$handoff"
}

append_record() {
    local lf="$1" rec="$2"
    printf '%s\n' "$rec" >> "$lf"
}

new_lease_id() {
    printf 'lease_%s_%s_%s' "$(date -u +%Y%m%dT%H%M%S)" "$$" "$RANDOM"
}

parse_common() {
    # Sets: LEASES_FILE, DB_FILE
    LEASES_FILE="$DEFAULT_LEASES"
    DB_FILE="$DEFAULT_DB"
}

cmd_create() {
    local session="" role="" budget="" expires="" budget_msgs="null" leases="$DEFAULT_LEASES" db="$DEFAULT_DB" usage=false
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --session) session="${2:?}"; shift 2 ;;
            --role) role="${2:?}"; shift 2 ;;
            --soft-budget) budget="${2:?}"; shift 2 ;;
            --expires-at) expires="${2:?}"; shift 2 ;;
            --leases) leases="${2:?}"; shift 2 ;;
            --db) db="${2:?}"; shift 2 ;;
            --usage-from-db) usage=true; shift ;;
            --budget-messages) budget_msgs="${2:?}"; shift 2 ;;
            *) die "create: unexpected arg: $1" ;;
        esac
    done
    [[ -n "$session" && -n "$role" && -n "$budget" && -n "$expires" ]] \
        || die "create requires --session --role --soft-budget --expires-at"
    iso_tz_or_die "--expires-at" "$expires"
    if [[ "$budget_msgs" != "null" ]]; then
        [[ "$budget_msgs" =~ ^[0-9]+$ ]] || die "--budget-messages must be a non-negative integer"
    fi
    local id; id="$(new_lease_id)"
    local usage_json="null"
    if $usage; then
        usage_json="$(usage_from_db "$db" "$session")" || die "usage query failed"
    fi
    mkdir -p "$(dirname "$leases")"
    local rec
    rec="$(jq -S -c -n \
        --arg id "$id" --arg session "$session" --arg role "$role" \
        --argjson budget "$budget" --arg expires "$expires" \
        --argjson budget_msgs "$budget_msgs" \
        --arg created "$(now_iso)" --argjson usage "$usage_json" \
        '{id: $id, session_id: $session, role: $role,
          soft_budget_tokens: $budget, expires_at: $expires,
          budget_messages: $budget_msgs,
          state: "active", created_at: $created, usage: $usage}')" \
        || die "failed to build lease record"
    acquire_lock "$leases"
    append_record "$leases" "$rec"
    release_lock
    printf '%s\n' "$rec"
}

cmd_check() {
    local id="" leases="$DEFAULT_LEASES" now="" db="$DEFAULT_DB" usage=false
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --id) id="${2:?}"; shift 2 ;;
            --leases) leases="${2:?}"; shift 2 ;;
            --now) now="${2:?}"; shift 2 ;;
            --db) db="${2:?}"; shift 2 ;;
            --usage-from-db) usage=true; shift ;;
            *) die "check: unexpected arg: $1" ;;
        esac
    done
    [[ -n "$id" ]] || die "check requires --id"
    [[ -n "$now" ]] && iso_tz_or_die "--now" "$now"
    [[ -f "$leases" ]] || die "no leases file at $leases"
    [[ -n "$now" ]] || now="$(now_iso)"

    acquire_lock "$leases"
    local last
    last="$(last_record_for "$leases" "$id")"
    [[ -n "$last" ]] || { release_lock; die "no lease with id $id in $leases"; }

    local state expires budget_msgs
    state="$(jq -r '.state' <<<"$last")"
    expires="$(jq -r '.expires_at' <<<"$last")"

    if [[ "$state" == "active" ]]; then
        local now_e exp_e trigger=""
        now_e="$(iso_to_epoch "$now")" || { release_lock; die "bad --now: $now"; }
        exp_e="$(iso_to_epoch "$expires")" || { release_lock; die "bad expires_at: $expires"; }
        if (( now_e > exp_e )); then
            trigger="time"
        elif $usage; then
            budget_msgs="$(jq -r '.budget_messages // empty' <<<"$last")"
            if [[ -n "$budget_msgs" && "$budget_msgs" != "null" ]]; then
                local live_mc
                live_mc="$(usage_from_db "$db" "$(jq -r '.session_id' <<<"$last")" | jq -r '.message_count')" \
                    || { release_lock; die "usage query failed"; }
                if (( live_mc > budget_msgs )); then trigger="budget"; fi
            fi
        fi
        if [[ -n "$trigger" ]]; then
            # State transition: expired + checkpoint-handoff record. NEVER a
            # kill instruction — respawn/kill decisions stay with the orchestrator.
            local exp_rec
            exp_rec="$(jq -S -c '.state = "expired"' <<<"$last")"
            append_record "$leases" "$exp_rec"
            append_handoff "$leases" "$id" "$trigger" "$now"
            last="$exp_rec"
        fi
    elif [[ "$state" == "expired" ]] && ! handoff_exists "$leases" "$id"; then
        # Healing: the expired→handoff append pair was interrupted (crash window).
        # Emit the missing handoff once; idempotent on the normal path.
        local trg="time"
        if (( $(iso_to_epoch "$now") <= $(iso_to_epoch "$expires") )); then trg="budget"; fi
        append_handoff "$leases" "$id" "$trg" "$now"
    fi
    release_lock
    printf '%s\n' "$last"
}

cmd_renew() {
    local id="" minutes="" leases="$DEFAULT_LEASES" now=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --id) id="${2:?}"; shift 2 ;;
            --extend-minutes) minutes="${2:?}"; shift 2 ;;
            --leases) leases="${2:?}"; shift 2 ;;
            --now) now="${2:?}"; shift 2 ;;
            *) die "renew: unexpected arg: $1" ;;
        esac
    done
    [[ -n "$id" && -n "$minutes" ]] || die "renew requires --id --extend-minutes"
    [[ "$minutes" =~ ^[0-9]+$ ]] || die "--extend-minutes must be a non-negative integer"
    [[ -f "$leases" ]] || die "no leases file at $leases"
    [[ -n "$now" ]] && iso_tz_or_die "--now" "$now"
    [[ -n "$now" ]] || now="$(now_iso)"

    acquire_lock "$leases"
    local last
    last="$(last_record_for "$leases" "$id")"
    [[ -n "$last" ]] || { release_lock; die "no lease with id $id in $leases"; }
    local state
    state="$(jq -r '.state' <<<"$last")"
    [[ "$state" == "active" ]] || { release_lock; die "renew refused: lease $id state=$state (only active leases renew)"; }
    local new_exp
    new_exp="$(epoch_to_iso "$(( $(iso_to_epoch "$(jq -r '.expires_at' <<<"$last")") + minutes * 60 ))")"
    local rec
    rec="$(jq -S -c --arg e "$new_exp" '.expires_at = $e' <<<"$last")"
    append_record "$leases" "$rec"
    release_lock
    printf '%s\n' "$rec"
}

cmd_release() {
    local id="" leases="$DEFAULT_LEASES" now=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --id) id="${2:?}"; shift 2 ;;
            --leases) leases="${2:?}"; shift 2 ;;
            --now) now="${2:?}"; shift 2 ;;
            *) die "release: unexpected arg: $1" ;;
        esac
    done
    [[ -n "$id" ]] || die "release requires --id"
    [[ -f "$leases" ]] || die "no leases file at $leases"
    [[ -n "$now" ]] && iso_tz_or_die "--now" "$now"
    [[ -n "$now" ]] || now="$(now_iso)"

    acquire_lock "$leases"
    local last
    last="$(last_record_for "$leases" "$id")"
    [[ -n "$last" ]] || { release_lock; die "no lease with id $id in $leases"; }
    local state
    state="$(jq -r '.state' <<<"$last")"
    [[ "$state" == "active" ]] || { release_lock; die "release refused: lease $id state=$state (only active leases release)"; }
    local rec
    rec="$(jq -S -c --arg ts "$now" '.state = "released" | .released_at = $ts' <<<"$last")"
    append_record "$leases" "$rec"
    release_lock
    printf '%s\n' "$rec"
}

case "${1:-}" in
    create) shift; cmd_create "$@" ;;
    check) shift; cmd_check "$@" ;;
    renew) shift; cmd_renew "$@" ;;
    release) shift; cmd_release "$@" ;;
    *) echo "usage: $SCRIPT_NAME {create|check|renew|release} ..." >&2; exit 1 ;;
esac
