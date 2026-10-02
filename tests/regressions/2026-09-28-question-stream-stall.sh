#!/usr/bin/env bash
set -euo pipefail

source_file="${OPENCODE_PROCESSOR_SOURCE:-$HOME/src/opencode/packages/opencode/src/session/processor.ts}"
[[ -f "$source_file" ]] || { printf 'FAIL: missing processor source: %s\n' "$source_file" >&2; exit 1; }

# Status gate: structural greps only enforce while the patch entry is active.
# Kill variants and explicit fixture runs set OPENCODE_PROCESSOR_SOURCE, so the
# gate yields and the full assertion set (and its polarity) still runs.
repo="$(cd "$(dirname "$0")/../.." && pwd)"
if [[ -z "${OPENCODE_PROCESSOR_SOURCE:-}" ]]; then
    entry="$repo/.sisyphus/patches/opencode--question-stream-stall-guard.md"
    status="$(grep -m1 -oP '^status:\s*"\K[^"]+' "$entry" 2>/dev/null || true)"
    if [[ "$status" != "active" ]]; then
        printf 'SKIP (deferred): patch opencode--question-stream-stall-guard status=%s — structural greps re-arm when the entry flips to active\n' "${status:-unknown}"
        exit 0
    fi
fi

# Structural regression: the call ID must be tracked on invocation, removed on
# either terminal event, and used to re-arm the same watchdog deadline.
for required in \
    'inFlightQuestions.add(value.id)' \
    'inFlightQuestions.delete(value.id)' \
    'inFlightQuestions.clear()' \
    'inFlightQuestions.size > 0' \
    'lastEvent = yield* Clock.currentTimeMillis' \
    'value.name.toLowerCase()' \
    '"mcp_question"' \
    'Effect.fail(new ProviderError.ResponseStreamError'; do
    if ! grep -Fq "$required" "$source_file"; then
        printf 'FAIL: question stall guard missing: %s\n' "$required" >&2
        exit 1
    fi
done

if [[ -n "${OPENCODE_BINARY_UNDER_TEST:-}" ]]; then
    grep -aq 'mcp_question' "$OPENCODE_BINARY_UNDER_TEST" || {
        printf 'FAIL: question marker absent from built binary\n' >&2
        exit 1
    }
fi

printf 'PASS: question stall guard and ordinary stall error path present (structural only)\n'
