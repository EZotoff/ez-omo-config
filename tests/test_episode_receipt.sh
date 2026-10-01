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
#   6. --checkpoint WITHOUT --phase on fresh dir + --resume-pointer → default phase 'session',
#      resume_pointer persisted, exit 0
#   7. hand-edited malformed receipt (claims: []) → verify exit 2
#   8. lint flags stale active episode and active-without-checkpoint; clean episode → exit 0
#   9. msg:<id>|<excerpt> evidence ref round-trip: append → verify pass → tamper stored
#      excerpt → verify digest-mismatch exit 2
#  10. receipt with two evidence entries, second tampered → verify exit 2 AND
#      receipt verified == false (per-receipt aggregation)
#  11. msg excerpt with literal trailing newline → verify passes (base64 framing)
#  12. advance to current phase refused; advance backwards to a done phase refused
#
#  13. --closeout: without closeout.md → exit 1, nothing written; with closeout.md →
#      kind=closeout receipt, closeout_status set, closeout phase auto-created,
#      manifest status closed + closed_at
#  14. lint: closed-without-closeout-receipt flagged; closed-with-receipt ok;
#      active all-phases-done-without-closeout flagged
#  15. --status without --closeout → usage error; --closeout with invalid status →
#      usage error; --closeout with --checkpoint → usage error
#  16. verify passes on a closed manifest carrying a closeout receipt (extended
#      schema round-trip)
#
# No network, no ports. Temp dirs tracked and removed via EXIT trap.


set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/../scripts/episode-receipt.sh"

PASS=0
FAIL=0

TMPDIRS=()
# Sets the nameref'd variable to a fresh temp dir and registers it for the
# EXIT trap in the PARENT shell (command substitution would run in a subshell
# and the trap would clean nothing).
new_tmpdir() {
    local -n ref=$1
    ref="$(mktemp -d)"
    TMPDIRS+=("$ref")
}
trap 'rm -rf "${TMPDIRS[@]}"' EXIT

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
    local d; new_tmpdir d
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
    local d; new_tmpdir d
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
    local d; new_tmpdir d
    fixture_manifest "$d/ep"
    local i
    for i in $(seq 1 10); do
        echo "ev-$i" > "$d/ev$i.txt"
    done
    local pids=()
    for i in $(seq 1 10); do
        bash "$SCRIPT" append "$d/ep" --phase design --claims "[\"claim $i\"]" --evidence "$d/ev$i.txt" >/dev/null 2>&1 &
        pids+=($!)
    done
    local pid st
    for pid in "${pids[@]}"; do
        wait "$pid" || { bad "S3 append job $pid exited non-zero"; return; }
    done
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
    local d; new_tmpdir d
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
    local d; new_tmpdir d
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
# --- Scenario 6: checkpoint without --phase, with --resume-pointer ---
s6() {
    local d; new_tmpdir d
    echo "s6 evidence" > "$d/ev.txt"
    run_isolated append "$d/ep-fresh" --checkpoint --intent "no-phase checkpoint" \
        --claims '["did stuff"]' --evidence-refs "$d/ev.txt" \
        --resume-pointer "resume at X" >/dev/null \
        || { bad "S6 checkpoint append failed"; return; }
    local mp="$d/ep-fresh/manifest.yaml"
    [[ -f "$mp" ]] || { bad "S6 manifest not auto-created"; return; }
    jq -e '.phases[0].receipts[0].resume_pointer == "resume at X"' "$mp" >/dev/null \
        || { bad "S6 resume_pointer not set"; return; }
    jq -e '.phases[0].name == "session" and .phases[0].receipts[0].phase == "session"' "$mp" >/dev/null \
        || { bad "S6 default phase not session"; return; }
    ok "S6 checkpoint without --phase: default session phase, resume_pointer set"
}

# --- Scenario 7: hand-edited malformed receipt (claims: []) → verify exit 2 ---
s7() {
    local d; new_tmpdir d
    echo "s7 evidence" > "$d/ev.txt"
    fixture_manifest "$d/ep"
    run_isolated append "$d/ep" --phase design --claims '["c"]' --evidence "$d/ev.txt" >/dev/null \
        || { bad "S7 append failed"; return; }
    # Hand-edit the manifest: break the receipt schema
    jq '(.phases[].receipts[] | select(.seq == 1) | .claims) = []' \
        "$d/ep/manifest.yaml" > "$d/ep/manifest.yaml.tmp" && mv "$d/ep/manifest.yaml.tmp" "$d/ep/manifest.yaml"
    local rc=0
    run_isolated verify "$d/ep" >/dev/null 2>&1 || rc=$?
    [[ $rc -eq 2 ]] || { bad "S7 malformed receipt verify exit=$rc (want 2)"; return; }
    ok "S7 malformed receipt (claims: []) → verify exit 2"
}

# --- Scenario 8: lint flags stale active + missing checkpoint; clean episode ok ---
s8() {
    local d; new_tmpdir d

    # (a) stale active episode: backdate started + receipt ts beyond 7 days
    echo "s8a evidence" > "$d/ev.txt"
    mkdir -p "$d/stale"
    fixture_manifest "$d/stale"
    run_isolated append "$d/stale" --phase design --claims '["old claim"]' \
        --evidence "$d/ev.txt" --checkpoint >/dev/null || { bad "S8 stale-fixture append failed"; return; }
    jq --arg old "2026-09-01T00:00:00Z" '
        .started = $old
        | (.phases[].receipts[].ts) = $old
    ' "$d/stale/manifest.yaml" > "$d/stale/manifest.yaml.tmp" && mv "$d/stale/manifest.yaml.tmp" "$d/stale/manifest.yaml"
    local rc=0
    run_isolated lint "$d/stale" >/dev/null 2>&1 || rc=$?
    [[ $rc -eq 1 ]] || { bad "S8 stale episode lint exit=$rc (want 1)"; return; }

    # (b) active with recent activity but no checkpoint receipt
    fixture_manifest "$d/nocheck"
    run_isolated append "$d/nocheck" --phase design --claims '["did work without checkpointing"]' >/dev/null \
        || { bad "S8 no-checkpoint fixture append failed"; return; }
    rc=0
    run_isolated lint "$d/nocheck" >/dev/null 2>&1 || rc=$?
    [[ $rc -eq 1 ]] || { bad "S8 active-no-checkpoint lint exit=$rc (want 1)"; return; }

    # (c) clean episode: recent checkpoint → lint exit 0
    echo "s8c evidence" > "$d/evc.txt"
    run_isolated append "$d/clean" --checkpoint --intent "clean episode" \
        --claims '["fresh work"]' --evidence "$d/evc.txt" >/dev/null \
        || { bad "S8 clean-fixture checkpoint failed"; return; }
    rc=0
    run_isolated lint "$d/clean" >/dev/null 2>&1 || rc=$?
    [[ $rc -eq 0 ]] || { bad "S8 clean episode lint exit=$rc (want 0)"; return; }
    ok "S8 lint: stale active flagged, missing checkpoint flagged, clean ok"
}

# --- Scenario 9: msg:<id>|<excerpt> evidence ref round-trip ---
s9() {
    local d; new_tmpdir d
    fixture_manifest "$d/ep"
    run_isolated append "$d/ep" --phase design --claims '["said the thing"]' \
        --evidence-refs 'msg:msg_123|agent claimed the build was green' >/dev/null \
        || { bad "S9 append with msg evidence ref failed"; return; }
    local mp="$d/ep/manifest.yaml"
    jq -e '
        .phases[].receipts[].evidence[0].path == "msg:msg_123"
        and (.phases[].receipts[].evidence[0].excerpt | type == "string")
    ' "$mp" >/dev/null || { bad "S9 msg evidence entry malformed"; return; }
    local want
    want="$(printf '%s' 'agent claimed the build was green' | sha256sum | awk '{print $1}')"
    jq -e --arg w "$want" '.phases[].receipts[].evidence[0].sha256 == $w' "$mp" >/dev/null \
        || { bad "S9 stored digest != sha256(excerpt bytes)"; return; }
    # verify pass (round-trip)
    run_isolated verify "$d/ep" >/dev/null 2>&1 \
        || { bad "S9 verify failed on untampered msg evidence"; return; }
    # tamper the stored excerpt → digest-mismatch, exit 2
    jq '(.phases[].receipts[].evidence[] | select(.path == "msg:msg_123") | .excerpt) = "tampered excerpt"' \
        "$mp" > "$mp.tmp" && mv "$mp.tmp" "$mp"
    local rc=0
    run_isolated verify "$d/ep" >/dev/null 2>&1 || rc=$?
    [[ $rc -eq 2 ]] || { bad "S9 tampered-excerpt verify exit=$rc (want 2)"; return; }
    local reason
    reason="$(jq -r '[.phases[].receipts[]][0].verified_reason' "$mp")"
    [[ "$reason" == "digest-mismatch" ]] || { bad "S9 tampered reason=$reason"; return; }
    ok "S9 msg evidence round-trip: pass → tampered excerpt → exit 2 digest-mismatch"
}

# --- Scenario 10: per-receipt aggregation (two entries, second tampered) ---
s10() {
    local d; new_tmpdir d
    echo "s10 first" > "$d/ev1.txt"
    echo "s10 second" > "$d/ev2.txt"
    fixture_manifest "$d/ep"
    run_isolated append "$d/ep" --phase design --claims '["two entries"]'         --evidence-refs "$d/ev1.txt,$d/ev2.txt" >/dev/null \
        || { bad "S10 append failed"; return; }
    echo "TAMPERED" > "$d/ev2.txt"
    local rc=0
    run_isolated verify "$d/ep" >/dev/null 2>&1 || rc=$?
    [[ $rc -eq 2 ]] || { bad "S10 verify exit=$rc (want 2)"; return; }
    local vflag reason
    vflag="$(jq -r '[.phases[].receipts[]][0].verified' "$d/ep/manifest.yaml")"
    reason="$(jq -r '[.phases[].receipts[]][0].verified_reason' "$d/ep/manifest.yaml")"
    [[ "$vflag" == "false" ]] || { bad "S10 receipt verified=$vflag (want false; passing entry must not overwrite)"; return; }
    [[ "$reason" == "digest-mismatch" ]] || { bad "S10 reason=$reason"; return; }
    ok "S10 two-entry receipt, second tampered → exit 2, receipt verified:false"
}

# --- Scenario 11: msg excerpt with literal trailing newline ---
s11() {
    local d; new_tmpdir d
    fixture_manifest "$d/ep"
    run_isolated append "$d/ep" --phase design --claims '["newline excerpt"]' \
        --evidence-refs $'msg:msg_x|excerpt ending with newline\n' >/dev/null \
        || { bad "S11 append with trailing-newline excerpt failed"; return; }
    run_isolated verify "$d/ep" >/dev/null 2>&1 \
        || { bad "S11 verify failed on trailing-newline excerpt"; return; }
    ok "S11 msg excerpt with trailing newline → verify passes"
}

# --- Scenario 12: advance forward-only (current / done targets refused) ---
s12() {
    local d; new_tmpdir d
    echo "s12 bytes" > "$d/ev.txt"
    fixture_manifest "$d/ep"
    run_isolated append "$d/ep" --phase design --claims '["c"]' --evidence "$d/ev.txt" >/dev/null \
        || { bad "S12 append failed"; return; }
    local rc=0
    # advance to the CURRENT phase → refused
    run_isolated advance "$d/ep" design >/dev/null 2>&1 || rc=$?
    [[ $rc -eq 4 ]] || { bad "S12 advance-to-current exit=$rc (want 4)"; return; }
    # successful forward advance design → build
    rc=0
    run_isolated advance "$d/ep" build >/dev/null 2>&1 || rc=$?
    [[ $rc -eq 0 ]] || { bad "S12 forward advance failed (exit=$rc)"; return; }
    # advance BACKWARDS to design (now done) → refused
    rc=0
    run_isolated advance "$d/ep" design >/dev/null 2>&1 || rc=$?
    [[ $rc -eq 4 ]] || { bad "S12 advance-backwards exit=$rc (want 4)"; return; }
    ok "S12 advance forward-only: current refused, backwards-to-done refused"
}

# --- Scenario 13: --closeout requires closeout.md; writes closeout receipt + closes manifest ---
s13() {
    local d; new_tmpdir d
    echo "work evidence" > "$d/ev.txt"
    fixture_manifest "$d/ep"
    run_isolated append "$d/ep" --phase design --claims '["work done"]' --evidence "$d/ev.txt" >/dev/null

    # (a) missing closeout.md → usage error (exit 1), nothing written
    local rc=0
    run_isolated append "$d/ep" --closeout --status degraded --claims '["closed with gaps"]' >/dev/null 2>&1 || rc=$?
    [[ $rc -eq 1 ]] || { bad "S13a missing-md append exit=$rc (want 1)"; return; }
    jq -e '.status == "active" and ([.phases[].receipts[]] | length) == 1' "$d/ep/manifest.yaml" >/dev/null \
        || { bad "S13a state mutated despite refusal"; return; }

    # (b) with closeout.md → closeout receipt + closed manifest
    printf '# Closeout\n\ncomplete.\n\ncloseout.status: degraded\n' > "$d/ep/closeout.md"
    rc=0
    run_isolated append "$d/ep" --closeout --status degraded --claims '["closed with gaps"]' >/dev/null 2>&1 || rc=$?
    [[ $rc -eq 0 ]] || { bad "S13b closeout append exit=$rc"; return; }
    local mp="$d/ep/manifest.yaml"
    jq -e '(
        .status == "closed"
        and .closeout_status == "degraded"
        and (.closed_at | type == "string" and length > 0)
        and ([.phases[] | select(.name == "closeout")] | length == 1)
        and ([.phases[] | select(.name == "closeout")][0].status == "done")
        and ([.phases[].receipts[] | select(.kind == "closeout")] | length == 1)
        and ([.phases[].receipts[] | select(.kind == "closeout")][0].closeout_status == "degraded")
        and ([.phases[].receipts[] | select(.kind == "closeout")][0].evidence | length >= 1)
        and ([.phases[].receipts[] | select(.kind == "closeout")][0].evidence[0].path | endswith("closeout.md"))
    )' "$mp" >/dev/null || { bad "S13b closeout manifest shape wrong"; return; }
    ok "S13 --closeout: md required (loud refusal), receipt kind=closeout, manifest closed+outcome"
}

# --- Scenario 14: lint rules (c) closed-without-receipt, (d) finished-but-never-closed ---
s14() {
    local d; new_tmpdir d
    echo "s14 evidence" > "$d/ev.txt"

    # (a) closed manifest WITHOUT closeout receipt → flagged
    fixture_manifest "$d/fake-closed"
    run_isolated append "$d/fake-closed" --phase design --claims '["c"]' --evidence "$d/ev.txt" >/dev/null
    jq '.status = "closed"' "$d/fake-closed/manifest.yaml" > "$d/fake-closed/manifest.yaml.tmp" \
        && mv "$d/fake-closed/manifest.yaml.tmp" "$d/fake-closed/manifest.yaml"
    local rc=0
    run_isolated lint "$d/fake-closed" >/dev/null 2>&1 || rc=$?
    [[ $rc -eq 1 ]] || { bad "S14a closed-without-receipt lint exit=$rc (want 1)"; return; }

    # (b) closed WITH closeout receipt → ok
    mkdir -p "$d/real-closeout"
    printf '# Closeout\n\nAll phases verified.\n\ncloseout.status: complete\n' > "$d/real-closeout/closeout.md"
    fixture_manifest "$d/real-closeout"
    run_isolated append "$d/real-closeout" --phase design --claims '["c"]' --evidence "$d/ev.txt" >/dev/null
    run_isolated append "$d/real-closeout" --closeout --status complete --claims '["closed"]' >/dev/null \
        || { bad "S14b closeout append failed"; return; }
    rc=0
    run_isolated lint "$d/real-closeout" >/dev/null 2>&1 || rc=$?
    [[ $rc -eq 0 ]] || { bad "S14b closed-with-receipt lint exit=$rc (want 0)"; return; }

    # (c) active, ALL phases done, no closeout receipt → flagged (finished-but-never-closed)
    fixture_manifest "$d/limbo"
    run_isolated append "$d/limbo" --phase design --claims '["c"]' --evidence "$d/ev.txt" --checkpoint >/dev/null
    jq '(.phases[].status) = "done"' "$d/limbo/manifest.yaml" > "$d/limbo/manifest.yaml.tmp" \
        && mv "$d/limbo/manifest.yaml.tmp" "$d/limbo/manifest.yaml"
    rc=0
    run_isolated lint "$d/limbo" >/dev/null 2>&1 || rc=$?
    [[ $rc -eq 1 ]] || { bad "S14c finished-never-closed lint exit=$rc (want 1)"; return; }
    ok "S14 lint: closed-without-receipt flagged, closed-with-receipt ok, finished-never-closed flagged"
}

# --- Scenario 15: flag pairing/enum usage errors ---
s15() {
    local d; new_tmpdir d
    fixture_manifest "$d/ep"
    local rc=0
    run_isolated append "$d/ep" --status complete --claims '["c"]' >/dev/null 2>&1 || rc=$?
    [[ $rc -eq 1 ]] || { bad "S15a --status without --closeout exit=$rc (want 1)"; return; }
    rc=0
    run_isolated append "$d/ep" --closeout --status banana --claims '["c"]' >/dev/null 2>&1 || rc=$?
    [[ $rc -eq 1 ]] || { bad "S15b invalid status exit=$rc (want 1)"; return; }
    rc=0
    run_isolated append "$d/ep" --closeout --checkpoint --status complete --claims '["c"]' >/dev/null 2>&1 || rc=$?
    [[ $rc -eq 1 ]] || { bad "S15c --closeout with --checkpoint exit=$rc (want 1)"; return; }
    rc=0
    run_isolated append "$d/ep" --closeout --claims '["c"]' >/dev/null 2>&1 || rc=$?
    [[ $rc -eq 1 ]] || { bad "S15d --closeout without --status exit=$rc (want 1)"; return; }
    ok "S15 closeout flag pairing/enum usage errors all refused"
}

# --- Scenario 16: verify round-trip on closed manifest with closeout receipt ---
s16() {
    local d; new_tmpdir d
    echo "s16 work" > "$d/ev.txt"
    fixture_manifest "$d/ep"
    run_isolated append "$d/ep" --phase design --claims '["c"]' --evidence "$d/ev.txt" >/dev/null
    printf '# Closeout\n\nDone.\n\ncloseout.status: complete\n' > "$d/ep/closeout.md"
    run_isolated append "$d/ep" --closeout --status complete --claims '["closed cleanly"]' >/dev/null \
        || { bad "S16 closeout append failed"; return; }
    local rc=0
    run_isolated verify "$d/ep" >/dev/null 2>&1 || rc=$?
    [[ $rc -eq 0 ]] || { bad "S16 verify on closed manifest exit=$rc (want 0)"; return; }
    # tamper closeout.md → digest-mismatch, exit 2
    echo "tampered" >> "$d/ep/closeout.md"
    rc=0
    run_isolated verify "$d/ep" >/dev/null 2>&1 || rc=$?
    [[ $rc -eq 2 ]] || { bad "S16 tampered closeout.md verify exit=$rc (want 2)"; return; }
    ok "S16 verify round-trip on closed manifest; tampered closeout.md → exit 2"
}

s1; s2; s3; s4; s5; s6; s7; s8; s9; s10; s11; s12; s13; s14; s15; s16

echo "----------------------------------------"
echo "episode-receipt tests: Pass: $PASS | Fail: $FAIL"
[[ $FAIL -eq 0 ]] || exit 1
exit 0
