#!/usr/bin/env bash
# Action-dispatch bijection gate (2026-10-02 postmortem).
#
# Root cause class this blocks: an action exists in the tick schema (tick.ts /
# types.ts ACTIONS) but has no dispatch site in service.ts — a "schema ghost".
# STEER and REFORMULATE shipped as ghosts on 2026-09-22 (c953be6: gates, texts,
# config, tests — zero call sites) and survived every review until 2026-10-02
# because green unit tests cannot see a missing call site.
#
# This gate enforces the bijection structurally AND runs the full supervisor
# unit suite + typecheck, which run_all.sh previously never executed.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUPERVISOR="$ROOT/supervisor"
TICK="$SUPERVISOR/src/tick.ts"
SERVICE="$SUPERVISOR/src/service.ts"
TYPES="$SUPERVISOR/src/types.ts"

echo "[dispatch-gate] 1/3 structural bijection: schema actions ↔ service dispatch"

# Extract the action enum members from the tick decision schema.
ACTIONS=$(grep -o 'action: z.enum(\[[^]]*\])' "$TICK" | sed 's/.*\[//; s/\].*//; s/"//g' | tr ',' '\n' | tr -d ' ')
test -n "$ACTIONS" || { echo "FAIL: could not parse action enum from $TICK"; exit 1; }

WRITE_PATH_ACTIONS="CONTINUE ESCALATE STEER REFORMULATE"
# APPROVE is a CONTINUE sub-mode (decision.mode === "approve"), not an enum
# member — structurally gated here instead (2026-10-03 Option C, rollout-staged).
grep -q 'decision.mode === "approve"' "$SERVICE" || { echo "FAIL: approve write path missing dispatch site in service.ts (schema ghost)"; fail=1; }
grep -q 'approveWriteText' "$SERVICE" || { echo "FAIL: approveWriteText never called in service.ts"; fail=1; }
fail=0
for action in $ACTIONS; do
  # Every action must appear in the compile-time exhaustiveness checker.
  if ! grep -q "case \"$action\":" "$SERVICE"; then
    echo "FAIL: action $action missing from assertDispatchHandlesEveryAction in service.ts"
    fail=1
  fi
  # Write-path actions must have a real dispatch site.
  if echo "$WRITE_PATH_ACTIONS" | grep -qw "$action"; then
    if ! grep -q "decision.action === \"$action\"" "$SERVICE"; then
      echo "FAIL: write-path action $action has NO dispatch site in service.ts (schema ghost)"
      fail=1
    fi
  fi
done
# The ACTIONS const in types.ts must match the tick schema enum (no drift between the two sources).
for action in $ACTIONS; do
  grep -q "\"$action\"" "$TYPES" || { echo "FAIL: action $action absent from ACTIONS in types.ts"; fail=1; }
done

echo "[dispatch-gate] 1b/3 injection single-flight tripwire (claim guard + root-filtered retry)"

CONSOLE="$SUPERVISOR/src/console.ts"
# The in-memory single-flight set must exist.
grep -q 'inFlight' "$CONSOLE" || { echo "FAIL: inFlight single-flight set missing from console.ts"; fail=1; }
# All three delivery paths must acquire the claim.
CLAIMS=$(grep -c 'this\.claim(' "$CONSOLE" || true)
test "$CLAIMS" -ge 3 || { echo "FAIL: claim guard missing on a delivery path (found $CLAIMS, need >=3)"; fail=1; }
RELEASES=$(grep -c 'this\.release(' "$CONSOLE" || true)
test "$RELEASES" -ge 3 || { echo "FAIL: release missing on a delivery path (found $RELEASES, need >=3)"; fail=1; }
# handleReply must claim AFTER the disposition check (panel claim-leak fix).
HANDLE_BODY=$(awk '/async handleReply\(/,/private async routeAnswered/' "$CONSOLE")
DISP_LINE=$(printf '%s\n' "$HANDLE_BODY" | grep -n 'applyDisposition' | head -1 | cut -d: -f1)
CLAIM_LINE=$(printf '%s\n' "$HANDLE_BODY" | grep -n 'this\.claim(' | head -1 | cut -d: -f1)
test -n "$DISP_LINE" && test -n "$CLAIM_LINE" && test "$DISP_LINE" -lt "$CLAIM_LINE" || { echo "FAIL: handleReply claims before the disposition check (claim-leak)"; fail=1; }
# retryPendingPropagations must be root-filtered and claim before probe.
RETRY_BODY=$(awk '/async retryPendingPropagations\(/,/async recoverAnswered/' "$CONSOLE")
printf '%s\n' "$RETRY_BODY" | grep -q 'item\.target\.root !== root' || { echo "FAIL: retryPendingPropagations is not root-filtered"; fail=1; }
printf '%s\n' "$RETRY_BODY" | grep -q 'this\.claim(' || { echo "FAIL: retryPendingPropagations does not claim"; fail=1; }
# recoverAnswered must claim per item.
RECOVER_BODY=$(awk '/async recoverAnswered\(/,/async handleReply\(/' "$CONSOLE")
printf '%s\n' "$RECOVER_BODY" | grep -q 'this\.claim(' || { echo "FAIL: recoverAnswered does not claim"; fail=1; }
# The service call site must pass the root to the retry pass.
grep -q 'retryPendingPropagations(root\.path' "$SERVICE" || { echo "FAIL: retryPendingPropagations call site does not pass root"; fail=1; }
test "$fail" -eq 0 || exit 1
echo "[dispatch-gate] bijection OK ($(echo "$ACTIONS" | tr '\n' ' '))"

echo "[dispatch-gate] 2/3 supervisor unit suite (bun test)"
(cd "$SUPERVISOR" && bun test)

echo "[dispatch-gate] 3/3 supervisor typecheck (tsc --noEmit)"
(cd "$SUPERVISOR" && bunx tsc --noEmit)

echo "[dispatch-gate] PASS"
