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

# Structural regression: local (non-provider-executed) tool calls must be tracked
# from tool-call to tool-result/tool-error, and a heartbeat must refresh the stall
# deadline while any such call is in flight — without removing the ordinary fail site.
#
# NOTE (rung coupling): these literals encode rung R1 (heartbeat closure +
# Effect.raceFirst(watchdog, heartbeat)). If task 6's A/B gate forces the R2
# (inline loop re-arm) or R3 (module-scope state) fallback, the literals below
# MUST be updated to the rung-equivalent markers in the SAME commit.
for required in \
    'localTools' \
    '!event.providerExecuted' \
    'Effect.raceFirst(watchdog, heartbeat)' \
    'stream-stall heartbeat: local tool execution in flight' \
    'ProviderError.ResponseStreamError(' \
    'LLM stream stalled for'; do
    if ! grep -Fq "$required" "$source_file"; then
        printf 'FAIL: local-tool stall exemption missing: %s\n' "$required" >&2
        exit 1
    fi
done

if [[ -n "${OPENCODE_BINARY_UNDER_TEST:-}" ]]; then
    grep -aq 'stream-stall heartbeat: local tool execution in flight' "$OPENCODE_BINARY_UNDER_TEST" || {
        printf 'FAIL: heartbeat marker absent from built binary\n' >&2
        exit 1
    }
fi

printf 'PASS: local-tool stall exemption and ordinary stall error path present (structural only)\n'
