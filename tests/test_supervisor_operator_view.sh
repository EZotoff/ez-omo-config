#!/usr/bin/env bash
# Supervisor operator-view.json atomic publication (orca-transition plan task 2).
# Covers: bounded card shape, single-image atomicity under concurrent readers,
# lastSeq never beyond incorporated card data, ≤15 s heartbeat republish,
# probe-noise exclusion, 10-minute quiet period (cards stay live, never grey).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$ROOT/supervisor"

if ! bun test test/operator-view.test.ts 2>&1; then
    printf 'supervisor operator-view: FAIL (bun test)\n' >&2
    exit 1
fi

# HARD BOUNDARY: the publisher must never write the ledger or any JSONL.
if grep -n "jsonl\|ledger.append\|Ledger" src/operator-view.ts; then
    printf 'supervisor operator-view: FAIL (ledger write path found in publisher)\n' >&2
    exit 1
fi

printf 'supervisor operator-view: PASS\n'
