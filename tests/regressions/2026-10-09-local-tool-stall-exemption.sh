#!/usr/bin/env bash
set -euo pipefail

source_file="${OPENCODE_PROCESSOR_SOURCE:-$HOME/src/opencode-wt-stall/packages/opencode/src/session/processor.ts}"
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

# Structural regression (rung R1 literals): locally-executed tools must be
# tracked (add gated on !providerExecuted, delete on tool-result/tool-error),
# a heartbeat must refresh the watchdog clock while the set is non-empty,
# and the watchdog fail site must be preserved.
# NOTE: if task 6's A/B gate escalates to rung R2 (inline loop re-arm) or R3
# (module-scope state), the R1-specific literals below (localTools set,
# Effect.raceFirst(watchdog, heartbeat), heartbeat log) MUST be updated to the
# rung-equivalent markers in the same commit (plan line: "If the rung changes
# from R1, task 9's structural-grep literals must be updated to match").
for required in \
    'const localTools = new Set<string>()' \
    '!event.providerExecuted' \
    'localTools.add(event.id)' \
    'localTools.delete(event.id)' \
    'localTools.size > 0' \
    'Effect.raceFirst(watchdog, heartbeat)' \
    'stream-stall heartbeat: local tool execution in flight' \
    'Effect.fail(new ProviderError.ResponseStreamError' \
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
