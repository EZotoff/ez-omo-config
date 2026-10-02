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
test "$fail" -eq 0 || exit 1
echo "[dispatch-gate] bijection OK ($(echo "$ACTIONS" | tr '\n' ' '))"

echo "[dispatch-gate] 2/3 supervisor unit suite (bun test)"
(cd "$SUPERVISOR" && bun test)

echo "[dispatch-gate] 3/3 supervisor typecheck (tsc --noEmit)"
(cd "$SUPERVISOR" && bunx tsc --noEmit)

echo "[dispatch-gate] PASS"
