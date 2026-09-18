#!/usr/bin/env bash
# integrity-triage.sh — gate between integrity-check failure and operator notification.
#
# Invoked by opencode-integrity-triage.service (OnFailure= of
# opencode-patch-integrity-check.service). Instead of alerting the operator on
# EVERY 30-minute failure cycle, triage:
#
#   1. re-runs the four integrity checks and classifies the failure
#   2. applies deterministic auto-remediation where safe
#        - provenance AMBER "runtime pending"  -> run the smoke matrix
#        - everything green again              -> clear stale alert marker, exit
#   3. spawns a headless agent for judgment-call failures (live-config drift:
#      legit in-progress work gets committed; damage/sandbox leakage is NOT
#      touched — agent reports TRIAGE-BLOCKED)
#   4. escalates to the operator (integrity-alert.sh: marker + critical
#      notify-send + journal) ONLY if the failure survives remediation AND
#      this exact failure fingerprint has not been escalated within
#      ESCALATION_DEDUPE_SECS. Repeat cycles for the same unresolved failure
#      are journal lines only — no more notification spam.
#
# Patch-verdict failures (STALE / VERSION-DRIFT / MISSING-TARGET) are never
# agent-fixed: they need the update-to-latest / patch reconcile procedure and
# escalate immediately with an actionable message.
#
# State: ~/.local/state/opencode/integrity-triage.json
# Exit codes: 0 = green or remediated; 1 = escalated to operator;
#             2 = infrastructure error (flock, jq missing).
set -euo pipefail

REPO="${EZ_OMO_CONFIG_REPO:-$HOME/ez-omo-config}"
STATE_DIR="$HOME/.local/state/opencode"
TRIAGE_STATE="$STATE_DIR/integrity-triage.json"
MARKER="$STATE_DIR/patch-integrity.alert"
FAILED_UNIT="${1:-unknown}"
ESCALATION_DEDUPE_SECS="${ESCALATION_DEDUPE_SECS:-43200}"   # 12h
AGENT_BUDGET_PER_DAY="${AGENT_BUDGET_PER_DAY:-2}"
AGENT_TIMEOUT_SECS="${AGENT_TIMEOUT_SECS:-900}"

CHECKS=(
  "verify:scripts/verify-live-patches.sh"
  "drift:scripts/check-live-config-drift.sh"
  "remote:scripts/check-remote-presence.sh"
  "provenance:scripts/check-provenance.sh"
)

log()  { systemd-cat -t integrity-triage -p "$1" <<< "$2" 2>/dev/null || printf '%s\n' "$2" >&2; }
info() { log info "$1"; }
warn() { log warning "$1"; }

mkdir -p "$STATE_DIR"
AGENT_OUT_FILE="$(mktemp "$STATE_DIR/triage-agent-output.XXXXXX")"
trap 'rm -f "$AGENT_OUT_FILE"' EXIT

# --- single-flight lock ------------------------------------------------------
exec 9>"$STATE_DIR/integrity-triage.lock"
if ! flock -n 9; then
    info "TRIAGE: another triage run holds the lock — skipping"
    exit 0
fi

command -v jq >/dev/null 2>&1 || { echo "TRIAGE-INFRA: jq missing" >&2; exit 2; }

# --- state helpers -----------------------------------------------------------
state_get() { jq -r "$1 // empty" "$TRIAGE_STATE" 2>/dev/null || true; }

state_write() { # $1=fingerprint $2=last_escalation_epoch $3=agent_date $4=agent_count
    jq -n --arg fp "$1" --argjson esc "$2" --arg d "$3" --argjson n "$4" \
        '{fingerprint: $fp, last_escalation: $esc, agent_date: $d, agent_runs: $n}' \
        > "$TRIAGE_STATE"
}

now="$(date +%s)"
today="$(date +%Y-%m-%d)"
st_fp="$(state_get .fingerprint)"
st_esc="$(state_get .last_escalation)"; st_esc="${st_esc:-0}"
st_ad="$(state_get .agent_date)";       st_ad="${st_ad:-}"
st_an="$(state_get .agent_runs)";       st_an="${st_an:-0}"
[[ "$st_ad" == "$today" ]] || st_an=0

# --- run checks --------------------------------------------------------------
# run_checks -> populates FAILING (space-separated labels) and FAIL_DETAILS
declare -A OUT
run_checks() {
    FAILING=""
    FAIL_DETAILS=""
    for entry in "${CHECKS[@]}"; do
        label="${entry%%:*}"; script="${entry#*:}"
        out="$(bash "$REPO/$script" 2>&1)" && rc=0 || rc=$?
        OUT[$label]="$out"
        if (( rc != 0 )); then
            FAILING+=" $label"
            FAIL_DETAILS+="[$label] $(grep -m2 -E 'FAIL|DRIFT|STALE|MISSING|VERSION-DRIFT|drift' <<<"$out" | tr '\n' '|' || true)"$'\n'
        fi
    done
    FAILING="${FAILING# }"
}

escalate() { # $1 = reason line for the operator
    local fp reason="$1"
    fp="$(printf '%s' "$reason" | sha256sum | cut -d' ' -f1)"
    if [[ "$fp" == "$st_fp" ]] && (( now - st_esc < ESCALATION_DEDUPE_SECS )); then
        info "TRIAGE: failure unchanged and escalated $((( (now - st_esc) / 60 ))) min ago — suppressed duplicate operator notification"
        return 1
    fi
    info "TRIAGE: escalation required (unit: $FAILED_UNIT): $reason"
    bash "$REPO/scripts/integrity-alert.sh" "$FAILED_UNIT" || true
    state_write "$fp" "$now" "$st_ad" "$st_an"
    return 0
}

agent_run() { # $1 = prompt; writes agent output to $AGENT_OUT_FILE; returns agent exit code.
# Must be called in the CURRENT shell (no $() capture) — the budget counter
# must persist; the drift test proved $() capture loses st_an to the subshell.
    if (( st_an >= AGENT_BUDGET_PER_DAY )); then
        warn "TRIAGE: agent budget exhausted ($st_an/$AGENT_BUDGET_PER_DAY today) — skipping agent remediation"
        return 99
    fi
    info "TRIAGE: dispatching headless triage agent (run $((st_an + 1))/$AGENT_BUDGET_PER_DAY today)"
    local rc
    printf '%s' "$1" | timeout "$AGENT_TIMEOUT_SECS" opencode run >"$AGENT_OUT_FILE" 2>&1 && rc=0 || rc=$?
    if (( rc == 124 )); then
        warn "TRIAGE: agent timed out after ${AGENT_TIMEOUT_SECS}s"
    fi
    st_an=$((st_an + 1))
    st_ad="$today"
    state_write "$st_fp" "$st_esc" "$st_ad" "$st_an"
    return "$rc"
}

success_exit() {
    if [[ -f "$MARKER" ]]; then
        rm -f "$MARKER"
        info "TRIAGE: cleared stale alert marker"
    fi
    state_write "" 0 "$st_ad" "$st_an"   # reset dedupe so a NEW failure notifies immediately
    info "TRIAGE: all integrity checks green — no operator action needed"
    exit 0
}

# --- 1. classify -------------------------------------------------------------
run_checks
if [[ -z "$FAILING" ]]; then
    if [[ -f "$MARKER" ]]; then
        info "TRIAGE: checks green on re-run — state was self-healed since the failed cycle"
    fi
    success_exit
fi
info "TRIAGE: failing checks:$([ -n "$FAILING" ] && printf ' %s' $FAILING)"

# --- 2. deterministic remediation: pending smokes (provenance AMBER) --------
if [[ " $FAILING " == *" provenance "* ]] || [[ " $FAILING " == *" verify "* ]]; then
    if grep -q 'runtime-pending [1-9]' <<<"${OUT[provenance]:-}${OUT[verify]:-}"; then
        info "TRIAGE: provenance runtime-pending detected — running smoke matrix"
        for smoke in "$REPO"/tests/smoke/smoke-*.sh; do
            [[ -f "$smoke" ]] || continue
            sname="$(basename "$smoke")"
            if s_out="$(timeout 300 bash "$smoke" 2>&1)"; then
                info "TRIAGE: smoke $sname -> $(tail -1 <<<"$s_out")"
            else
                warn "TRIAGE: smoke $sname FAILED/errored (rc=$?) — will escalate"
            fi
        done
        run_checks
        if [[ -z "$FAILING" ]]; then
            info "TRIAGE: smoke matrix cleared the pending state"
            success_exit
        fi
    fi
fi

# --- 3. classify remaining failures ------------------------------------------
# Patch-verdict failures need the human reconcile procedure — escalate, no agent.
verify_out="${OUT[verify]:-}"
if [[ -n "$verify_out" ]] && grep -qE '^(STALE|VERSION-DRIFT|MISSING-TARGET|SCHEMA-VIOLATION) ' <<<"$verify_out" \
   && ! grep -q '0 stale | 0 missing-target | 0 version-drift' <<<"$verify_out"; then
    escalate "patch-verdict failure in verify-live-patches — run the update-to-latest / patch reconcile procedure" || true
    exit 1
fi

# --- 4. agent remediation for judgment-call failures --------------------------
if [[ " $FAILING " == *" drift "* ]]; then
    diff_summary="$(git -C "$REPO" status --porcelain -- configs/ 2>/dev/null | head -10)"
    a_rc=0
    agent_run "You are the patch-integrity triage agent for the ez-omo-config repo at $REPO.

The live-config drift check is failing because these paths under configs/ are uncommitted:
$diff_summary

Decide whether this is deliberate in-progress work or damage:
1. Inspect the actual diff (git -C $REPO diff -- configs/ and read enough of the changed files).
   2. If the changes look like coherent, deliberate work (config/doc edits with sensible content):
   stage exactly those configs/ paths and create ONE conventional commit
   (type(scope): subject, e.g. 'docs(agent): note integrity triage behavior').
   3. If the changes look like damage, gutted config, sandbox leakage, or you are unsure:
   change NOTHING and reply with a line starting 'TRIAGE-BLOCKED:' plus the reason.
Never touch files outside configs/, never revert, never force anything.

    Finish by printing either the commit hash you created or the TRIAGE-BLOCKED line." >"$AGENT_OUT_FILE" || a_rc=$?
    info "TRIAGE: agent finished (rc=$a_rc): $(head -c 400 "$AGENT_OUT_FILE" | tr '\n' ' ')"
    run_checks
fi

if [[ " $FAILING " == *" remote "* ]]; then
    a_rc=0
    agent_run "You are the patch-integrity triage agent. The check-remote-presence check for the
ez-omo-config repo at $REPO is failing: an active patch entry cites fork commit(s) that are
not reachable on the EZotoff/oh-my-openagent remote. Inspect the failing output in the journal
(unit opencode-patch-integrity-check.service) and the patch entries under $REPO/.sisyphus/patches/.
If the cited commits exist locally in the fork clone and are complete, push the corresponding
branch to origin (this is the documented mandatory procedure, AGENTS.md Cooperation Contract
item 8). If anything is incomplete or ambiguous, change NOTHING and reply 'TRIAGE-BLOCKED: reason'.
    Finish with either the pushed branch/commit info or a TRIAGE-BLOCKED line." >"$AGENT_OUT_FILE" || a_rc=$?
    info "TRIAGE: agent finished (rc=$a_rc): $(head -c 400 "$AGENT_OUT_FILE" | tr '\n' ' ')"
    run_checks
fi

# --- 5. final verdict ---------------------------------------------------------
if [[ -z "$FAILING" ]]; then
    info "TRIAGE: auto-remediated (unit: $FAILED_UNIT) — no operator action needed"
    command -v notify-send >/dev/null 2>&1 && \
        notify-send -u low 'OpenCode integrity: auto-remediated' \
            'A failing integrity check was triaged and fixed automatically. See journal: integrity-triage' || true
    success_exit
fi

escalate "unresolved after triage (checks failing:$([ -n "$FAILING" ] && printf ' %s' $FAILING)) — details: $FAIL_DETAILS" || true
exit 1
