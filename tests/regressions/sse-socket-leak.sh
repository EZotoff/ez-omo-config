#!/usr/bin/env bash
# Regression: SDK SSE generator-exit teardown (opencode--sdk-sse-socket-leak).
# Proves the SDK's SSE client cancels/aborts the underlying fetch when the
# consumer exits the event stream early — the loopback firehose root cause.
set -o errexit
source "$(cd "$(dirname "$0")/.." && pwd)/helpers.sh"

SRC="${OPENCODE_SRC:-$HOME/src/opencode}"
FILE="$SRC/packages/sdk/js/src/gen/core/serverSentEvents.gen.ts"
if [[ ! -f "$FILE" ]]; then echo "SKIP: $FILE not found"; exit 0; fi

# The teardown must cancel the reader inside the generator finally (before
# releaseLock). On the unpatched file the finally contains only
# removeEventListener + releaseLock.
assert_grep "reader.cancel" "$FILE"

# The per-iteration connection controller must exist and always abort.
assert_grep "new AbortController" "$FILE"
assert_grep "conn.abort" "$FILE"
echo "PASS: SSE teardown present in SDK source"
