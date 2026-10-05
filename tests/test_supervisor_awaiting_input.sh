#!/usr/bin/env bash
# Awaiting-operator-input guard gate (2026-10-05 incident).
#
# Root cause class this blocks: the supervisor intervened (kick_start CONTINUE)
# into a session whose last assistant message trailed a RUNNING question-tool
# part — the operator's answer dialog was open and the injected text collided
# with it (ses_ef4ef9abaffe, 2026-10-05 08:20:48). The fix has three layers:
#   1. tick suppression at decision time (awaitingOperatorAnswer on scan.messages),
#   2. a write-time guard — ALL supervisor-authored intervention writes route
#      through guardedPrompt (createGuardedPrompt),
#   3. transcript rendering of the pending ask.
#
# This gate enforces layer 2 structurally (schema-ghost tripwire): no raw
# intervention promptAsync may appear in service.ts outside the two sanctioned
# sites — the human operator-answer propagation (deliverPropagation) and the
# guardedPrompt wiring lambda itself.
#
# Structural check only; the behavioral suite runs via tests/test_supervisor_dispatch.sh
# (bun test + tsc) and tests/run_all.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVICE="$ROOT/supervisor/src/service.ts"
GUARD="$ROOT/supervisor/src/awaiting-input.ts"

fail=0

# Exactly two raw client.promptAsync sites are sanctioned: the operator-answer
# propagation and the guardedPrompt wiring lambda.
raw=$(grep -c 'client\.promptAsync(' "$SERVICE" || true)
if [ "$raw" -ne 2 ]; then
  echo "FAIL: expected exactly 2 raw client.promptAsync sites in service.ts (operator-answer propagation + guardedPrompt wiring), found $raw"
  fail=1
fi
grep -q 'deliverPropagation: async (input)' "$SERVICE" || { echo "FAIL: operator-answer propagation site (deliverPropagation) missing"; fail=1; }
grep -q 'promptAsync: (sessionID, root, text) => client.promptAsync(sessionID, root, text)' "$SERVICE" || { echo "FAIL: guardedPrompt wiring lambda missing"; fail=1; }

# All four intervention write paths must route through the guard.
wired=$(grep -c 'await guardedPrompt(' "$SERVICE" || true)
if [ "$wired" -lt 4 ]; then
  echo "FAIL: expected >=4 guardedPrompt write sites (approve/continue/steer/reformulate), found $wired — an intervention path bypasses the awaiting-operator guard (schema ghost)"
  fail=1
fi

# Decision-time suppression must consult the predicate on the scan snapshot.
grep -q 'awaitingOperatorAnswer(scan.messages)' "$SERVICE" || { echo "FAIL: tick-suppression predicate missing at decision time in service.ts"; fail=1; }
grep -q 'awaiting-operator-input' "$GUARD" || { echo "FAIL: stable skip-reason prefix missing from awaiting-input.ts"; fail=1; }

test "$fail" -eq 0 || exit 1
echo "[awaiting-input-gate] PASS (raw promptAsync=2, guarded writes=$wired, decision-time suppression present)"
