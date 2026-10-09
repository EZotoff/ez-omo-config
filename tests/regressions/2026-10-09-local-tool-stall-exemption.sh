#!/usr/bin/env bash
set -euo pipefail

# Default source is the main checkout, per the plan (structural greps enforce
# after the patch entry flips active). Fixture/kill runs override it via
# OPENCODE_PROCESSOR_SOURCE; the fix itself lives in ~/src/opencode-wt-stall
# (commit acc3dc0eb6) until it lands.
source_file="${OPENCODE_PROCESSOR_SOURCE:-$HOME/src/opencode/packages/opencode/src/session/processor.ts}"
[[ -f "$source_file" ]] || { printf 'FAIL: missing processor source: %s\n' "$source_file" >&2; exit 1; }

# Status gate: structural greps only enforce while the patch entry is active.
# Kill variants and explicit fixture runs set OPENCODE_PROCESSOR_SOURCE, so the
# gate yields and the full assertion set (and its polarity) still runs.
repo="$(cd "$(dirname "$0")/../.." && pwd)"
if [[ -z "${OPENCODE_PROCESSOR_SOURCE:-}" ]]; then
    entry="$repo/.sisyphus/patches/opencode--local-tool-stall-exemption.md"
    status="$(grep -m1 -oP '^status:\s*"\K[^"]+' "$entry" 2>/dev/null || true)"
    if [[ "$status" != "active" ]]; then
        printf 'SKIP (deferred): patch opencode--local-tool-stall-exemption status=%s — structural greps re-arm when the entry flips to active\n' "${status:-unknown}"
        exit 0
    fi
fi

# Structural regression (rung R1): local tool executions must be tracked on
# tool-call, removed on tool-result/tool-error, and raced via heartbeat alongside
# the watchdog so a local tool run does not trip the stream-stall abort.
# NOTE: these literals encode rung R1 (`Effect.raceFirst(watchdog, heartbeat)`).
# If the A/B gate (plan task 6) escalates to rung R2/R3, these literals MUST be
# updated in the same commit as the rework.
for required in \
    'localTools' \
    '!event.providerExecuted' \
    'Effect.raceFirst(watchdog, heartbeat)' \
    'stream-stall heartbeat: local tool execution in flight' \
    'ResponseStreamError' \
    'LLM stream stalled for'; do
    if ! grep -Fq "$required" "$source_file"; then
        printf 'FAIL: local-tool stall exemption missing: %s\n' "$required" >&2
        exit 1
    fi
done

if [[ -n "${OPENCODE_BINARY_UNDER_TEST:-}" ]]; then
    grep -aq 'stream-stall heartbeat: local tool execution in flight' "$OPENCODE_BINARY_UNDER_TEST" || {
        printf 'FAIL: local-tool heartbeat marker absent from built binary\n' >&2
        exit 1
    }
fi

printf 'PASS: local-tool stall exemption tracking + heartbeat present, ordinary stall error path preserved (structural only)\n'
