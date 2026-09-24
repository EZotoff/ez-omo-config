#!/usr/bin/env bash
#
# test_execution_record_lint.sh — W2.4 QA scenarios for scripts/execution-record-lint.sh
# Plan: .omo/plans/workflow-standardization.md (W2 QA row:
# "F-wave REJECT without actionable finding → lint fails the record").
#
# Scenarios (binary pass each):
#   1. valid synthetic plan (baseline + checked F-box + APPROVE + REJECT w/
#      severity finding) → lint exit 0
#   2. checked boxes without Execution Record baseline → lint exit 1
#   3. checked F-box without F#n verdict line → lint exit 1
#   4. F#n: REJECT without severity finding or APPROVE resolution → lint exit 1
#   5. REJECT resolved by later APPROVE (real-record shape) → lint exit 0
#   6. good reviews-ledger fixture (fenced json per round) → ledger exit 0
#   7. bad reviews-ledger fixture (missing fields / bad verdict) → exit 1
#   8. REAL .omo/plans/workflow-standardization.md passes plan lint
#   9. sweep mode over the real .omo/plans/ dir exits 0 (advisory
#      needs-disposition lines do not fail the sweep)
#
# No network, no ports. Temp dirs removed via EXIT trap.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LINT="$SCRIPT_DIR/../scripts/execution-record-lint.sh"
PLANS_DIR="$SCRIPT_DIR/../.omo/plans"
REAL_PLAN="$PLANS_DIR/workflow-standardization.md"

PASS=0
FAIL=0

TMPDIRS=()
new_tmpdir() {
    local -n ref=$1
    ref="$(mktemp -d)"
    TMPDIRS+=("$ref")
}
trap 'rm -rf "${TMPDIRS[@]}"' EXIT

ok()  { echo "PASS: $1"; PASS=$((PASS + 1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

# --- Scenario 1: valid synthetic plan passes ---
s1() {
    local d; new_tmpdir d
    cat > "$d/plan.md" <<'EOF'
# Plan

1. [x] Do the thing
2. [ ] Do the next thing

## Final Verification Wave

F1. [x] Requirements audit — APPROVED round 1
F2. [x] Code-quality review — APPROVED after fixes

## Execution Record

Execution baseline: 0123456789abcdef0123456789abcdef01234567

F#1: APPROVE — all requirements verified, tests/run_all.sh exit 0
F#2: REJECT — (CRITICAL) F#2 race in writer path: required_change add flock around append
F#2: APPROVE — delta review confirmed flock fix at scripts/foo.sh:42
EOF
    if bash "$LINT" plan "$d/plan.md" >/dev/null 2>&1; then
        ok "S1 valid synthetic plan passes"
    else
        bad "S1 valid synthetic plan failed lint"
    fi
}

# --- Scenario 2: missing baseline fails ---
s2() {
    local d; new_tmpdir d
    cat > "$d/plan.md" <<'EOF'
# Plan

1. [x] Do the thing

## Execution Record

F#1: APPROVE — evidence tests/run_all.sh exit 0
EOF
    local rc=0
    bash "$LINT" plan "$d/plan.md" >/dev/null 2>&1 || rc=$?
    if [[ $rc -eq 1 ]]; then
        ok "S2 missing baseline line fails"
    else
        bad "S2 missing baseline exit=$rc (want 1)"
    fi
}

# --- Scenario 3: checked F-box without F#n verdict line fails ---
s3() {
    local d; new_tmpdir d
    cat > "$d/plan.md" <<'EOF'
# Plan

1. [x] Do the thing

## Final Verification Wave

F1. [x] Requirements audit — APPROVED round 1

## Execution Record

Execution baseline: 0123456789abcdef0123456789abcdef01234567

F#2: APPROVE — evidence elsewhere
EOF
    local rc=0
    bash "$LINT" plan "$d/plan.md" >/dev/null 2>&1 || rc=$?
    if [[ $rc -eq 1 ]]; then
        ok "S3 checked F-box without F#n verdict line fails"
    else
        bad "S3 unchecked-verdict exit=$rc (want 1)"
    fi
}

# --- Scenario 4: REJECT without severity finding or resolution fails ---
s4() {
    local d; new_tmpdir d
    cat > "$d/plan.md" <<'EOF'
# Plan

1. [x] Do the thing

## Final Verification Wave

F1. [x] Requirements audit

## Execution Record

Execution baseline: 0123456789abcdef0123456789abcdef01234567

F#1: REJECT — did not like it, unspecified concerns
EOF
    local rc=0
    bash "$LINT" plan "$d/plan.md" >/dev/null 2>&1 || rc=$?
    if [[ $rc -eq 1 ]]; then
        ok "S4 REJECT without actionable severity finding fails"
    else
        bad "S4 bare-REJECT exit=$rc (want 1)"
    fi
}

# --- Scenario 5: REJECT resolved by later APPROVE (real-record shape) passes ---
s5() {
    local d; new_tmpdir d
    cat > "$d/plan.md" <<'EOF'
# Plan

1. [x] Do the thing

## Final Verification Wave

F1. [x] Requirements audit — APPROVED round 2

## Execution Record

Execution baseline: 0123456789abcdef0123456789abcdef01234567

Round 1: F#1: REJECT — missing schema fields, no lint subcommand (oracle, ses_x)
Round 2: F#1: APPROVE — delta review: all findings confirmed fixed file:line
EOF
    if bash "$LINT" plan "$d/plan.md" >/dev/null 2>&1; then
        ok "S5 REJECT superseded by later APPROVE passes (documented loosening)"
    else
        bad "S5 resolved-REJECT record failed lint"
    fi
}

# --- Scenario 6: good reviews-ledger fixture passes ---
s6() {
    local d; new_tmpdir d
    cat > "$d/plan.reviews.md" <<'EOF'
# Reviews — plan

- R1: REJECT, 2 blockers (see block).

```json
{
  "verdict": "REJECT",
  "round": 1,
  "budget": {"standard_used": 1, "standard_max": 4, "extensions_used": 0, "extensions_max": 2},
  "plan_digest": "0123456789abcdef0123456789abcdef01234567",
  "findings": [
    {"locator": "scripts/foo.sh:42", "severity": "CRITICAL", "claim": "race on append",
     "required_change": "wrap append in flock", "evidence": "two writers interleaved",
     "blocking_rationale": "corrupts manifest"}
  ],
  "disposition": "delta applied",
  "remaining_risks": []
}
```

```json
{
  "verdict": "OKAY",
  "round": 2,
  "budget": {"standard_used": 2, "standard_max": 4, "extensions_used": 0, "extensions_max": 2},
  "plan_digest": "0123456789abcdef0123456789abcdef01234567",
  "findings": [],
  "disposition": "accepted",
  "remaining_risks": "none material"
}
```
EOF
    if bash "$LINT" ledger "$d/plan.reviews.md" >/dev/null 2>&1; then
        ok "S6 good reviews-ledger fixture passes"
    else
        bad "S6 good ledger fixture failed"
    fi
}

# --- Scenario 7: bad reviews-ledger fixture fails ---
s7() {
    local d; new_tmpdir d
    cat > "$d/bad.reviews.md" <<'EOF'
# Reviews — bad plan

```json
{
  "verdict": "MAYBE",
  "round": 1,
  "findings": [
    {"locator": "x", "severity": "CRITICAL"}
  ]
}
```
EOF
    local rc=0
    bash "$LINT" ledger "$d/bad.reviews.md" >/dev/null 2>&1 || rc=$?
    if [[ $rc -eq 1 ]]; then
        ok "S7 bad reviews-ledger fixture (bad verdict, missing fields) fails"
    else
        bad "S7 bad ledger exit=$rc (want 1)"
    fi
}

# --- Scenario 8: real workflow-standardization.md passes ---
s8() {
    [[ -f "$REAL_PLAN" ]] || { bad "S8 real plan missing: $REAL_PLAN"; return; }
    if bash "$LINT" plan "$REAL_PLAN" >/dev/null 2>&1; then
        ok "S8 real workflow-standardization.md passes plan lint"
    else
        bad "S8 real workflow-standardization.md failed lint"
    fi
}

# --- Scenario 9: sweep over real plans dir exits 0 ---
s9() {
    [[ -d "$PLANS_DIR" ]] || { bad "S9 plans dir missing: $PLANS_DIR"; return; }
    local rc=0
    bash "$LINT" plans "$PLANS_DIR" >/dev/null 2>&1 || rc=$?
    if [[ $rc -eq 0 ]]; then
        ok "S9 sweep over real .omo/plans passes (advisory needs-disposition tolerated)"
    else
        bad "S9 real plans sweep exit=$rc (want 0)"
    fi
}

s1; s2; s3; s4; s5; s6; s7; s8; s9

echo "----------------------------------------"
echo "execution-record-lint tests: Pass: $PASS | Fail: $FAIL"
[[ $FAIL -eq 0 ]] || exit 1
exit 0
