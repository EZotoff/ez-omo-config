#!/usr/bin/env bash
#
# test_agent_lifecycle.sh — W3.2/W3.3 QA scenarios for agent-lease.sh and
# spawn-health-check.sh. Plan: .omo/plans/workflow-standardization.md §W3.
#
#   8. --usage-from-db attaches message/part counts (read-only)
#   9. over-budget lease (budget_messages exceeded, --usage-from-db on
#      check) → expired + handoff with trigger: "budget"
#  10. healing: expired state without a handoff record → check emits the
#      missing handoff exactly once
#  11. naive ISO timestamps (no Z / offset) rejected for --expires-at and --now
#  12. health-check with a missing DB → one parseable JSON line (verdict
#      unknown, error set), exit 0
#  13. respawn-record: allows the first respawn, refuses the second (--max 1)
#
# No writes to the LIVE opencode.db (scratch fixture DBs only). All sqlite
# access to the live DB is mode=ro. Scratch leases/state files via --leases
# / --state-file. Temp dirs removed via EXIT trap.
#
# Live-session scenarios (S6, S8) SKIP with a message when the live DB is
# absent or has no qualifying session — they never fail on an empty DB.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LEASE="$SCRIPT_DIR/../scripts/agent-lease.sh"
HEALTH="$SCRIPT_DIR/../scripts/spawn-health-check.sh"
DB="${TEST_DB:-$HOME/.local/share/opencode/opencode.db}"

PASS=0
FAIL=0
TMPDIRS=()

new_tmpdir() {
    local -n ref=$1
    ref="$(mktemp -d)"
    TMPDIRS+=("$ref")
}
trap 'rm -rf "${TMPDIRS[@]}"' EXIT

ok()   { echo "PASS: $1"; PASS=$((PASS + 1)); }
bad()  { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

run_isolated() {
    local script="$1"; shift
    env -i PATH="$PATH" HOME="${HOME:-/tmp}" bash "$script" "$@"
}

lease_field() { # file id field -> last record's field
    jq -r --arg id "$2" 'select(.id == $id) | .'"$3" "$1" | tail -n 1
}

# --- Scenario 1: create → check active ---
s1() {
    local d; new_tmpdir d
    local lf="$d/leases.jsonl"
    local rec
    rec="$(run_isolated "$LEASE" create --session ses_t1 --role worker \
        --soft-budget 50000 --expires-at "2030-01-01T00:00:00Z" --leases "$lf")" \
        || { bad "S1 create"; return; }
    local id; id="$(jq -r .id <<<"$rec")"
    local out
    out="$(run_isolated "$LEASE" check --id "$id" --leases "$lf")" \
        || { bad "S1 check exit"; return; }
    [[ "$(jq -r .state <<<"$out")" == "active" ]] || { bad "S1 state != active"; return; }
    [[ "$(jq -r .session_id <<<"$out")" == "ses_t1" ]] || { bad "S1 session_id"; return; }
    [[ "$(jq -r .soft_budget_tokens <<<"$out")" == "50000" ]] || { bad "S1 budget"; return; }
    ok "S1 create→check active"
}

# --- Scenario 2: past expires_at → expired + handoff record, no kill text ---
s2() {
    local d; new_tmpdir d
    local lf="$d/leases.jsonl"
    local id
    id="$(run_isolated "$LEASE" create --session ses_t2 --role replay \
        --soft-budget 1000 --expires-at "2020-01-01T00:00:00Z" --leases "$lf" | jq -r .id)" \
        || { bad "S2 create"; return; }
    local out
    out="$(run_isolated "$LEASE" check --id "$id" --leases "$lf")" \
        || { bad "S2 check exit"; return; }
    [[ "$(jq -r .state <<<"$out")" == "expired" ]] || { bad "S2 state != expired"; return; }
    local handoff
    handoff="$(jq -c --arg id "$id" 'select(.handoff == true and .lease_id == $id)' "$lf")" \
        || { bad "S2 scan"; return; }
    [[ -n "$handoff" ]] || { bad "S2 no handoff record"; return; }
    jq -e '.reason == "budget_exhausted" and .action == "checkpoint_handoff"' <<<"$handoff" >/dev/null \
        || { bad "S2 handoff fields"; return; }
    grep -qi 'kill' "$lf" && { bad "S2 kill text present"; return; }
    ok "S2 expired + checkpoint_handoff record"
}

# --- Scenario 3: renew extends ---
s3() {
    local d; new_tmpdir d
    local lf="$d/leases.jsonl"
    local id
    id="$(run_isolated "$LEASE" create --session ses_t3 --role worker \
        --soft-budget 50000 --expires-at "2030-01-01T00:00:00Z" --leases "$lf" | jq -r .id)"
    local out
    out="$(run_isolated "$LEASE" renew --id "$id" --extend-minutes 30 --leases "$lf")" \
        || { bad "S3 renew exit"; return; }
    [[ "$(jq -r .expires_at <<<"$out")" == "2030-01-01T00:30:00Z" ]] \
        || { bad "S3 expires_at not extended: $(jq -r .expires_at <<<"$out")"; return; }
    ok "S3 renew extends expires_at"
}

# --- Scenario 4: release sets state; second release refused ---
s4() {
    local d; new_tmpdir d
    local lf="$d/leases.jsonl"
    local id
    id="$(run_isolated "$LEASE" create --session ses_t4 --role worker \
        --soft-budget 50000 --expires-at "2030-01-01T00:00:00Z" --leases "$lf" | jq -r .id)"
    local out
    out="$(run_isolated "$LEASE" release --id "$id" --leases "$lf")" \
        || { bad "S4 release exit"; return; }
    [[ "$(jq -r .state <<<"$out")" == "released" ]] || { bad "S4 state != released"; return; }
    if run_isolated "$LEASE" release --id "$id" --leases "$lf" >/dev/null 2>&1; then
        bad "S4 second release should fail"; return
    fi
    ok "S4 release + idempotence refusal"
}

# --- Scenario 5: health-check nonexistent id → unknown, exit 0 ---
s5() {
    local out rc=0
    out="$(run_isolated "$HEALTH" ses_doesnotexist123 --db "$DB")" || rc=$?
    [[ $rc -eq 0 ]] || { bad "S5 exit=$rc (probe must exit 0)"; return; }
    [[ "$(jq -r .verdict <<<"$out")" == "unknown" ]] || { bad "S5 verdict: $out"; return; }
    [[ "$(jq -r .exists <<<"$out")" == "false" ]] || { bad "S5 exists=true"; return; }
    ok "S5 unknown session → verdict unknown, exit 0"
}

# --- Scenario 6: health-check against a real live session → healthy ---
s6() {
    [[ -f "$DB" ]] || { echo "SKIP: S6 (no db at $DB)"; return; }
    local sid
    sid="$(python3 - "$DB" <<'PYEOF'
import sqlite3, sys
con = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True)
row = con.execute(
    "select m.session_id from message m "
    "where (select count(*) from message m2 where m2.session_id = m.session_id limit 1) >= 1 "
    "limit 1"
).fetchone()
con.close()
print(row[0] if row else "")
PYEOF
    )"
    [[ -n "$sid" ]] || { echo "SKIP: S6 (no session with messages)"; return; }
    local out rc=0
    out="$(run_isolated "$HEALTH" "$sid" --db "$DB")" || rc=$?
    [[ $rc -eq 0 ]] || { bad "S6 exit=$rc"; return; }
    [[ "$(jq -r .verdict <<<"$out")" == "healthy" ]] || { bad "S6 verdict: $out"; return; }
    [[ "$(jq -r .message_count <<<"$out")" -ge 1 ]] || { bad "S6 message_count"; return; }
    ok "S6 live session ($sid) → healthy"
}

# --- Scenario 7: spawning window via fixture DB ---
s7() {
    local d; new_tmpdir d
    local fdb="$d/fixture.db"
    python3 - "$fdb" <<'PYEOF'
import sqlite3, sys, time
con = sqlite3.connect(sys.argv[1])
con.execute("create table session (id text primary key, time_created integer)")
con.execute("create table message (id text, session_id text, time_created integer)")
now_ms = int(time.time() * 1000)
con.execute("insert into session values ('ses_fresh', ?)", (now_ms - 60_000,))       # 1 min old, 0 msgs
con.execute("insert into session values ('ses_stale', ?)", (now_ms - 30 * 60_000,))  # 30 min old, 0 msgs
con.commit(); con.close()
PYEOF
    local out rc=0
    out="$(run_isolated "$HEALTH" ses_fresh --db "$fdb")" || rc=$?
    [[ $rc -eq 0 && "$(jq -r .verdict <<<"$out")" == "spawning" ]] \
        || { bad "S7 fresh: $out rc=$rc"; return; }
    out="$(run_isolated "$HEALTH" ses_stale --db "$fdb")" || rc=$?
    [[ $rc -eq 0 && "$(jq -r .verdict <<<"$out")" == "zero_token" ]] \
        || { bad "S7 stale: $out rc=$rc"; return; }
    out="$(run_isolated "$HEALTH" ses_fresh --db "$fdb" --probe-window 0)" || rc=$?
    [[ $rc -eq 0 && "$(jq -r .verdict <<<"$out")" == "zero_token" ]] \
        || { bad "S7 window-0: $out rc=$rc"; return; }
    ok "S7 spawning/zero_token windows"
}

# --- Scenario 8: --usage-from-db attaches counts (read-only) ---
s8() {
    [[ -f "$DB" ]] || { echo "SKIP: S8 (no db)"; return; }
    local sid
    sid="$(python3 - "$DB" <<'PYEOF'
import sqlite3, sys
con = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True)
row = con.execute(
    "select session_id from message group by session_id having count(*) >= 1 limit 1"
).fetchone()
con.close()
print(row[0] if row else "")
PYEOF
    )"
    [[ -n "$sid" ]] || { echo "SKIP: S8 (no session)"; return; }
    local d; new_tmpdir d
    local rec
    rec="$(run_isolated "$LEASE" create --session "$sid" --role worker \
        --soft-budget 1000 --expires-at "2030-01-01T00:00:00Z" \
        --leases "$d/leases.jsonl" --usage-from-db --db "$DB")" \
        || { bad "S8 create exit"; return; }
    jq -e --argjson m 1 '.usage.message_count >= $m and .usage.part_count >= 0' <<<"$rec" >/dev/null \
        || { bad "S8 usage fields: $(jq -c .usage <<<"$rec")"; return; }
    ok "S8 --usage-from-db attaches counts"
}


# --- Scenario 9: over-budget ACTIVE lease → expired + handoff trigger budget ---
s9() {
    local d; new_tmpdir d
    local fdb="$d/fixture.db"
    python3 - "$fdb" <<'PYEOF'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
con.execute("create table message (id text, session_id text, time_created integer)")
con.execute("create table part (id text, session_id text)")
con.executemany("insert into message values (?, 'ses_bud', 0)", [(str(i),) for i in range(5)])
con.commit(); con.close()
PYEOF
    local lf="$d/leases.jsonl" id
    id="$(run_isolated "$LEASE" create --session ses_bud --role worker \
        --soft-budget 50000 --expires-at "2030-01-01T00:00:00Z" \
        --budget-messages 2 --leases "$lf" | jq -r .id)" \
        || { bad "S9 create"; return; }
    local out
    out="$(run_isolated "$LEASE" check --id "$id" --leases "$lf" --usage-from-db --db "$fdb")" \
        || { bad "S9 check exit"; return; }
    [[ "$(jq -r .state <<<"$out")" == "expired" ]] || { bad "S9 state != expired"; return; }
    local handoff
    handoff="$(jq -c --arg id "$id" 'select(.handoff == true and .lease_id == $id)' "$lf")" \
        || { bad "S9 scan"; return; }
    jq -e '.reason == "budget_exhausted" and .action == "checkpoint_handoff" and .trigger == "budget"' \
        <<<"$handoff" >/dev/null \
        || { bad "S9 handoff trigger: $handoff"; return; }
    ok "S9 over-budget → handoff trigger budget"
}

# --- Scenario 10: healing emits the missing handoff exactly once ---
s10() {
    local d; new_tmpdir d
    local lf="$d/leases.jsonl" id
    id="$(run_isolated "$LEASE" create --session ses_heal --role replay \
        --soft-budget 1000 --expires-at "2020-01-01T00:00:00Z" --leases "$lf" | jq -r .id)" \
        || { bad "S10 create"; return; }
    # Simulate the crash window: expire the lease with the handoff records stripped.
    run_isolated "$LEASE" check --id "$id" --leases "$lf" >/dev/null
    grep -v '"handoff":true' "$lf" > "$lf.healed" && mv "$lf.healed" "$lf"
    run_isolated "$LEASE" check --id "$id" --leases "$lf" >/dev/null \
        || { bad "S10 healing check exit"; return; }
    local n
    n="$(jq -r --arg id "$id" 'select(.handoff == true and .lease_id == $id) | 1' "$lf" | wc -l | tr -d ' ')"
    [[ "$n" -eq 1 ]] || { bad "S10 handoff count after heal: $n"; return; }
    run_isolated "$LEASE" check --id "$id" --leases "$lf" >/dev/null
    n="$(jq -r --arg id "$id" 'select(.handoff == true and .lease_id == $id) | 1' "$lf" | wc -l | tr -d ' ')"
    [[ "$n" -eq 1 ]] || { bad "S10 handoff duplicated on re-check: $n"; return; }
    ok "S10 healing emits missing handoff once"
}

# --- Scenario 11: naive ISO timestamps rejected ---
s11() {
    local d; new_tmpdir d
    local lf="$d/leases.jsonl"
    if run_isolated "$LEASE" create --session ses_naive --role worker \
        --soft-budget 1 --expires-at "2030-01-01T00:00:00" --leases "$lf" >/dev/null 2>&1; then
        bad "S11 naive --expires-at accepted"; return
    fi
    local id
    id="$(run_isolated "$LEASE" create --session ses_naive --role worker \
        --soft-budget 1 --expires-at "2030-01-01T00:00:00Z" --leases "$lf" | jq -r .id)" \
        || { bad "S11 create"; return; }
    if run_isolated "$LEASE" check --id "$id" --leases "$lf" --now "2030-01-01T01:00:00" >/dev/null 2>&1; then
        bad "S11 naive --now accepted"; return
    fi
    ok "S11 naive ISO rejected (--expires-at, --now)"
}

# --- Scenario 12: health-check missing DB → JSON + exit 0 ---
s12() {
    local d; new_tmpdir d
    local out rc=0
    out="$(run_isolated "$HEALTH" ses_x --db "$d/nonexistent.db")" || rc=$?
    [[ $rc -eq 0 ]] || { bad "S12 exit=$rc (probe must exit 0)"; return; }
    jq -e '.verdict == "unknown" and (.error | length > 0)' <<<"$out" >/dev/null \
        || { bad "S12 output not always-JSON unknown: $out"; return; }
    out="$(run_isolated "$HEALTH" ses_x --db "$d/nonexistent.db" --probe-window abc)" || rc=$?
    [[ $rc -eq 0 ]] || { bad "S12 invalid-window exit=$rc"; return; }
    jq -e '.verdict == "unknown" and (.error | length > 0)' <<<"$out" >/dev/null \
        || { bad "S12 invalid-window output: $out"; return; }
    ok "S12 missing DB / invalid window → JSON unknown, exit 0"
}

# --- Scenario 13: respawn-record allows 1 then refuses ---
s13() {
    local d; new_tmpdir d
    local sf="$d/respawn-state.jsonl" out
    out="$(run_isolated "$HEALTH" --respawn-record --session ses_resp --max 1 --state-file "$sf")" \
        || { bad "S13 first respawn-record exit"; return; }
    jq -e '.respawn_allowed == true and .respawn_n == 1' <<<"$out" >/dev/null \
        || { bad "S13 first: $out"; return; }
    out="$(run_isolated "$HEALTH" --respawn-record --session ses_resp --max 1 --state-file "$sf")" \
        || { bad "S13 second respawn-record exit"; return; }
    jq -e '.respawn_allowed == false and .respawn_n == 1' <<<"$out" >/dev/null \
        || { bad "S13 second (refusal): $out"; return; }
    ok "S13 respawn-record allows 1 then refuses"
}

s1; s2; s3; s4; s5; s6; s7; s8; s9; s10; s11; s12; s13

echo
echo "agent-lifecycle: PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
