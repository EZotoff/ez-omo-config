#!/usr/bin/env bash
# Regression: SSE subscriber queues bounded (opencode--sse-queue-bounded).
set -o errexit
source "$(cd "$(dirname "$0")/.." && pwd)/helpers.sh"
SRC="${OPENCODE_SRC:-$HOME/src/opencode}"
E="$SRC/packages/opencode/src/server/routes/instance/httpapi/handlers/event.ts"
G="$SRC/packages/opencode/src/server/routes/instance/httpapi/handlers/global.ts"
[ -f "$E" ] || { echo "SKIP: $E missing"; exit 0; }
assert_grep "Queue.sliding" "$E"
if grep -q "Queue.unbounded<EventV2.Payload>" "$E"; then
  echo "FAIL: instance /event queue is unbounded again"; exit 1
fi
assert_grep 'bufferSize: 256, strategy: "sliding"' "$G"
echo "PASS: SSE subscriber queues bounded (sliding 256)"
