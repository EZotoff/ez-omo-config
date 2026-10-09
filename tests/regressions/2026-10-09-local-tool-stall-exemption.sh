#!/usr/bin/env bash
set -euo pipefail

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

# Structural regression: local tool calls must be tracked on invocation
# (provider-executed tools excluded), the heartbeat must race the watchdog,
# and the original stall fail site must remain intact.
#
# NOTE: if task 6's A/B gate demotes rung R1 to a fallback rung (R2/R3), the
# literals below MUST be updated to match the shipped mechanism in the SAME
# commit as the patch entry — see plan section "Fallback ladder".
for required in \
    'localTools' \
    '!event.providerExecuted' \
    'Effect.raceFirst(watchdog, heartbeat)' \
    'stream-stall heartbeat: local tool execution in flight' \
    'new ProviderError.ResponseStreamError(`LLM stream stalled for'; do
    if ! grep -Fq "$required" "$source_file"; then
        printf 'FAIL: local tool stall exemption missing: %s\n' "$required" >&2
        exit 1
    fi
done

if [[ -n "${OPENCODE_BINARY_UNDER_TEST:-}" ]]; then
    grep -aq 'stream-stall heartbeat: local tool execution in flight' "$OPENCODE_BINARY_UNDER_TEST" || {
        printf 'FAIL: heartbeat marker absent from built binary\n' >&2
        exit 1
    }
fi

printf 'PASS: local tool stall exemption and stall fail site present (structural only)\n'
