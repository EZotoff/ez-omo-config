#!/usr/bin/env bash
# Supervisor journal→ledger continuation bridge (crashsafe plan task 10).
# Covers: one tagged journal alert -> exactly one TICK_DECIDED ESCALATE row
# with continuation fields; cursor survives restart; fingerprint dedupe;
# different uuid imports once; ZERO promptAsync call sites in the bridge.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$ROOT/supervisor"

if ! bun test test/journalbridge.test.ts 2>&1; then
    printf 'supervisor journal bridge: FAIL (bun test)\n' >&2
    exit 1
fi

# HARD BOUNDARY: the bridge must never gain session-writing authority.
if grep -n "promptAsync(\|prompt_async" src/journalbridge.ts; then
    printf 'supervisor journal bridge: FAIL (promptAsync found in bridge)\n' >&2
    exit 1
fi

printf 'supervisor journal bridge: PASS\n'
