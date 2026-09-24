#!/usr/bin/env bash
#
# test_workorder_lint.sh — W3.1 QA scenarios for scripts/workorder-lint.sh
# Plan: .omo/plans/workflow-standardization.md (TODO 11; spec docs/workorders.md).
#
# Scenarios (binary pass each):
#   1. valid open workorder → exit 0
#   2. completed workorder (status: done) without teardown receipt → exit 1
#   3. missing Scope files → exit 1
#   4. --template output passes its own lint (round-trip) → exit 0
#   5. completed with closeout.status receipt + all checklist checked → exit 0
#   6. episode-receipt form also satisfies the receipt rule → exit 0
#   7. post-hoc drift: completed with unchecked checklist item → exit 1
#   8. escalation section without a named trigger → exit 1
#   9. named trigger + status: done → exit 1 (escalated work stays open)
#
# No network, no ports. Temp dirs tracked and removed via EXIT trap.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/../scripts/workorder-lint.sh"

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

# expect <label> <want_rc> <cmd...>
expect_rc() {
    local label="$1" want="$2"; shift 2
    local rc=0
    "$@" >/dev/null 2>&1 || rc=$?
    if [[ "$rc" -eq "$want" ]]; then
        ok "$label (exit=$rc)"
    else
        bad "$label (exit=$rc, want $want)"
    fi
}

valid_open() {
    cat <<'EOF'
# Workorder: retry-log-rotate

intent: rotate retry-plugin log weekly
budget: 30m
status: open

## Scope

- configs/opencode/provider-connect-retry.mjs

## Teardown checklist

- [ ] log rotation verified locally

## Teardown receipt

<!-- pending -->
EOF
}

completed_good() {
    cat <<'EOF'
# Workorder: retry-log-rotate

intent: rotate retry-plugin log weekly
budget: 30m
status: done

## Scope

- configs/opencode/provider-connect-retry.mjs

## Teardown checklist

- [x] log rotation verified locally

## Teardown receipt

closeout.status: complete
EOF
}


# --- Scenario 1: valid open workorder passes ---
s1() {
    local d; new_tmpdir d
    valid_open > "$d/wo.md"
    expect_rc "S1 valid open workorder" 0 bash "$SCRIPT" "$d/wo.md"
}

# --- Scenario 2: completed without teardown receipt fails ---
s2() {
    local d; new_tmpdir d
    completed_good | sed '/^closeout.status:/d' > "$d/wo.md"
    expect_rc "S2 completed without teardown receipt" 1 bash "$SCRIPT" "$d/wo.md"
}

# --- Scenario 3: missing Scope files fails ---
s3() {
    local d; new_tmpdir d
    valid_open | sed '/^- configs\//d' > "$d/wo.md"
    expect_rc "S3 missing scope files" 1 bash "$SCRIPT" "$d/wo.md"
}

# --- Scenario 4: --template output passes lint (round-trip) ---
s4() {
    local d; new_tmpdir d
    bash "$SCRIPT" --template > "$d/tpl.md" || { bad "S4 --template exited non-zero"; return; }
    expect_rc "S4 --template round-trip" 0 bash "$SCRIPT" "$d/tpl.md"
}

# --- Scenario 5: completed with receipt + all checked passes ---
s5() {
    local d; new_tmpdir d
    completed_good > "$d/wo.md"
    expect_rc "S5 completed + closeout.status receipt" 0 bash "$SCRIPT" "$d/wo.md"
}

# --- Scenario 6: episode-receipt form satisfies the receipt rule ---
s6() {
    local d; new_tmpdir d
    completed_good | sed 's|^closeout.status: complete$|episode-receipt: .omo/episodes/retry-log-rotate/manifest.yaml seq 3|' > "$d/wo.md"
    expect_rc "S6 completed + episode-receipt receipt" 0 bash "$SCRIPT" "$d/wo.md"
}

# --- Scenario 7: post-hoc drift — completed with unchecked item fails ---
s7() {
    local d; new_tmpdir d
    completed_good | sed 's/^- \[x\]/- [ ]/' > "$d/wo.md"
    expect_rc "S7 completed with unchecked checklist item" 1 bash "$SCRIPT" "$d/wo.md"
}

# --- Scenario 8: escalation section without a named trigger fails ---
s8() {
    local d; new_tmpdir d
    valid_open | sed 's/^<!-- pending -->/## Escalation\n\nthis got big/' > "$d/wo.md"
    expect_rc "S8 escalation without named trigger" 1 bash "$SCRIPT" "$d/wo.md"
}

# --- Scenario 9: named trigger + status: done fails (escalated stays open) ---
s9() {
    local d; new_tmpdir d
    cat > "$d/wo.md" <<'EOF'
# Workorder: retry-log-rotate

intent: rotate retry-plugin log weekly
budget: 30m
status: done

## Scope

- configs/opencode/provider-connect-retry.mjs

## Teardown checklist

- [x] log rotation verified locally

## Escalation

scope-drift

## Teardown receipt

closeout.status: complete
EOF
    expect_rc "S9 escalated trigger + status done" 1 bash "$SCRIPT" "$d/wo.md"
}

s1; s2; s3; s4; s5; s6; s7; s8; s9

echo "----------------------------------------"
echo "workorder-lint tests: Pass: $PASS | Fail: $FAIL"
[[ $FAIL -eq 0 ]] || exit 1
exit 0
