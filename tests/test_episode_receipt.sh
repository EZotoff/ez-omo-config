#!/usr/bin/env bash
#
# test_episode_receipt.sh — W1 QA scenarios for scripts/episode-receipt.sh
# Plan: .omo/plans/workflow-standardization.md (W1 QA table).
#
# Scenarios (binary pass each):
#   1. append→verify across two separate invocations → exit 0, digest match, seq monotonic
#   2. tamper evidence after append → verify non-zero, receipt verified:false
#   3. 10 concurrent appends → flock holds, all present, sequences unique+monotonic
#   4. advance without verify-pass → refused, exit non-zero
#   5. --checkpoint on no-manifest episode → minimal manifest auto-created containing the receipt
#
# No network, no ports. Temp dirs under $(mktemp -d).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/../scripts/episode-receipt.sh"

PASS=0
FAIL=0

ok()   { echo "PASS: $1"; PASS=$((PASS + 1)); }
bad()  { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

fixture_manifest() {
    # $1 = dir (created if missing)
    mkdir -p "$1"
    cat > "$1/manifest.yaml" <<'EOF'
{"schema":"0.2","episode":"test-ep","project":"/tmp","intent":"test episode","started":"2026-09-24T00:00:00Z","status":"active","lane":"full","owner":"agent","current_phase":"design","phases":[{"name":"design","status":"in_progress","receipts":[],"sessions":[]},{"name":"build","status":"pending","receipts":[],"sessions":[]}],"learnings":[],"follow_ups":[]}
EOF
}

# Clean env per invocation to simulate separate sessions
run_isolated() {
    env -i PATH="$PATH" HOME="${HOME:-/tmp}" bash "$SCRIPT" "$@"
}

# --- Scenario 1: append→verify across two separate invocations ---
s1() {
    local d; d="$(mktemp -d)"
    echo "evidence-one" > "$d/ev1.txt"
    fixture_manifest "$d/ep"
    if ! run_isolated append "$d/ep" --phase design --claims '["claim one"]' --evidence "$d/ev1.txt" --session ses_s1a >/dev/null; then
        bad "S1 first append"; return
    fi
    if ! run_isolated append "$d/ep" --phase design --claims '["claim two"]' --evidence "$d/ev1.txt" --session ses_s1b >/dev/null; then
        bad "S1 second append (separate session)"; return
    fi
    run_isolated verify "$d/ep" >/dev/null
    local vrc=$?
    [[ $vrc -eq 0 ]] || { bad "S1 verify exit=$vrc"; return; }
    local seqs digests
    seqs="$(jq -r '[.phases[].receipts[].seq] | @csv' "$d/ep/manifest.yaml")"
    [[ "$seqs" == "1,2" ]] || { bad "S1 sequence not monotonic: $seqs"; return; }
    digests="$(jq -r '[.phases[].receipts[].evidence[].sha256] | unique | length == 1' "$d/ep/manifest.yaml")"
    [[ "$digests" == "true" ]] || { bad "S1 digest mismatch across receipts"; return; }
    local want
    want="$(sha256sum "$d/ev1.txt" | awk '{print $1}')"
    jq -e --arg d "$want" '.phases[].receipts[].evidence[] | .sha256 == $d' "$d/ep/manifest.yaml" >/dev/null \
        || { bad "S1 stored digest != sha256(file bytes)"; return; }
    ok "S1 append→verify two sessions, digest match, seq monotonic"
}

# --- Scenario 2: tamper evidence after append ---
s2() {
    local d; d="$(mktemp -d)"
    echo "original bytes" > "$d/ev.txt"
    fixture_manifest "$d/ep"
    run_isolated append "$d/ep" --phase design --claims '["c"]' --evidence "$d/ev.txt" >/dev/null
    echo "TAMPERED" > "$d/ev.txt"
    local rc=0
    run_isolated verify "$d/ep" >/dev/null 2>&1 || rc=$?
    [[ $rc -ne 0 ]] || { bad "S2 verify unexpectedly passed after tamper"; return; }
    local vflag reason
    vflag="$(jq -r '[.phases[].receipts[0] | select(. != null)] | .[0].verified' "$d/ep/manifest.yaml")"
    reason="$(jq -r '[.phases[].receipts[0] | select(. != null)] | .[0].verified_reason' "$d/ep/manifest.yaml")"
    [[ "$vflag" == "false" ]] || { bad "S2 receipt not marked verified:false (got $vflag)"; return; }
    [[ "$reason" == "digest-mismatch" ]] || { bad "S2 reason=$reason"; return; }
    # receipt kept (not dropped)
    jq -e '([.phases[].receipts[]] | length) == 1' "$d/ep/manifest.yaml" >/dev/null \
        || { bad "S2 receipt dropped"; return; }
    ok "S2 tamper → verify exit=$rc, verified:false, receipt kept"
}

# --- Scenario 3: 10 concurrent appends ---
s3() {
    local d; d="$(mktemp -d)"
    fixture_manifest "$d/ep"
    local i
    for i in $(seq 1 10); do
        echo "ev-$i" > "$d/ev$i.txt"
    done
    for i in $(seq 1 10); do
        bash "$SCRIPT" append "$d/ep" --phase design --claims "[\"claim $i\"]" --evidence "$d/ev$i.txt" >/dev/null 2>&1 &
    done
    wait
    local count uniq sorted
    count="$(jq -r '[.phases[].receipts[].seq] | length' "$d/ep/manifest.yaml")"
    uniq="$(jq -r '[.phases[].receipts[].seq] | unique | length' "$d/ep/manifest.yaml")"
    sorted="$(jq -r 'if ([.phases[].receipts[].seq] == ([.phases[].receipts[].seq] | sort)) then "yes" else "no" end' "$d/ep/manifest.yaml")"
    [[ "$count" == "10" ]] || { bad "S3 count=$count (want 10)"; return; }
    [[ "$uniq" == "10" ]] || { bad "S3 duplicate seqs (unique=$uniq)"; return; }
    [[ "$sorted" == "yes" ]] || { bad "S3 seqs not monotonic"; return; }
    ok "S3 10 concurrent appends: flock held, all present, seq unique+monotonic"
}

# --- Scenario 4: advance without verify-pass ---
s4() {
    local d; d="$(mktemp -d)"
    echo "s4 bytes" > "$d/ev.txt"
    fixture_manifest "$d/ep"
    run_isolated append "$d/ep" --phase design --claims '["c"]' --evidence "$d/ev.txt" >/dev/null
    echo "MUTATED" > "$d/ev.txt"   # verify will hard-fail
    local rc=0
    run_isolated advance "$d/ep" build >/dev/null 2>&1 || rc=$?
    [[ $rc -ne 0 ]] || { bad "S4 advance unexpectedly succeeded"; return; }
    local cur
    cur="$(jq -r '.current_phase' "$d/ep/manifest.yaml")"
    [[ "$cur" == "design" ]] || { bad "S4 pointer moved despite refusal ($cur)"; return; }
    ok "S4 advance refused without verify-pass (exit=$rc), pointer unmoved"
}

# --- Scenario 5: --checkpoint auto-creates minimal manifest ---
s5() {
    local d; d="$(mktemp -d)"
    echo "checkpoint evidence" > "$d/ev.txt"
    mkdir -p "$d/ep-new"
    run_isolated append "$d/ep-new" --checkpoint --intent "in-session episode" \
        --phase session --claims '["did the thing"]' --evidence "$d/ev.txt" --session ses_x >/dev/null \
        || { bad "S5 checkpoint append failed"; return; }
    [[ -f "$d/ep-new/manifest.yaml" ]] || { bad "S5 manifest not auto-created"; return; }
    jq -e '
        .schema == "0.2" and .lane == "in-session" and .status == "active"
        and .phases[0].name == "session"
        and ((.phases[0].receipts | length) == 1)
    ' "$d/ep-new/manifest.yaml" >/dev/null || { bad "S5 minimal manifest malformed"; return; }
    jq -e '.phases[0].receipts[0].kind == "checkpoint"' "$d/ep-new/manifest.yaml" >/dev/null \
        || { bad "S5 receipt not inside manifest"; return; }
    # single source of truth: no sidecar receipt files in the episode dir
    local extras
    extras="$(find "$d/ep-new" -maxdepth 1 -type f ! -name manifest.yaml ! -name .lock | wc -l | tr -d ' ')"
    [[ "$extras" == "0" ]] || { bad "S5 sidecar files present"; return; }
    ok "S5 --checkpoint auto-created minimal manifest containing the receipt"
}

s1; s2; s3; s4; s5

echo "----------------------------------------"
echo "episode-receipt tests: Pass: $PASS | Fail: $FAIL"
[[ $FAIL -eq 0 ]] || exit 1
exit 0
