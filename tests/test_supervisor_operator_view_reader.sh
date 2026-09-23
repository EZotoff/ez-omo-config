#!/usr/bin/env bash
# Supervisor operator-view.json reader-side contract (orca-transition plan task 3).
# Covers: schema validation, receipt-time staleness (29/31 s), future-skew (+6 s),
# older-generation freeze, lastSeq gap/regression freeze, monotonic-timer freshness,
# ±5 s wall-clock jump → fresh read, atomic-replace reread, read-error, 10-minute
# quiet period; each case demonstrated against a naive (validation-bypassing) reader.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$ROOT/supervisor"

if ! bun test test/operator-view-reader.test.ts 2>&1; then
    printf 'supervisor operator-view reader: FAIL (bun test)\n' >&2
    exit 1
fi

# HARD BOUNDARY: the reader is the portable contract side — it must not depend on
# the Supervisor loop (service/ledger/queue/poller) and must import the publisher
# type-only, so it can be copied into Orca unchanged.
if grep -nE 'from "\./(service|ledger|queue|poller|collect|reconcile|statemachine)"' src/operator-view-reader.ts; then
    printf 'supervisor operator-view reader: FAIL (Supervisor-loop dependency found)\n' >&2
    exit 1
fi
if grep -nE '^import \{[^}]*\} from "\./operator-view"' src/operator-view-reader.ts; then
    printf 'supervisor operator-view reader: FAIL (publisher import must be type-only)\n' >&2
    exit 1
fi

printf 'supervisor operator-view reader: PASS\n'
