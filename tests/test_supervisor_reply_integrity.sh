#!/usr/bin/env bash
# Stuck-pendingAnswers-propagation gate (2026-10-12 beacon-reply-integrity).
#
# Root cause class this blocks: a recovered outbox answer (pendingAnswers) was
# re-recorded forever because markAnswered's idempotency guard was
# latest-state-only. A re-decide revalidation moved the item off "answered", so
# every retry cycle re-submitted the SAME accepted replyEventID and appended
# another QUEUE_REPLY_RECEIVED row (5,985 receipts for one recovered item).
# Three layers fix it:
#   1. durable idempotency — markAnswered no-ops when the item's lifecycle
#      already carries an "answered" event with the same replyEventID (queue.ts),
#   2. origin preservation — pendingAnswers entries carry {text, replyEventID,
#      channelID} so a retry re-submits the ORIGINAL reply identity, not a
#      synthesized recovered_<itemID> (console.ts),
#   3. stale-drop — a recovered answer whose premise changed is dropped on
#      re-decide so the retry loop terminates (console.ts).
#
# Structural tripwire only; the behavioral suite (3 cases) runs via
# tests/test_supervisor_dispatch.sh (bun test + tsc) and tests/run_all.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QUEUE="$ROOT/supervisor/src/queue.ts"
CONSOLE="$ROOT/supervisor/src/console.ts"
TESTFILE="$ROOT/supervisor/test/beacon-reply-integrity.test.ts"

fail=0

# Layer 1: durable idempotency guard in markAnswered.
grep -q 'event.state === "answered" && event.replyEventID === replyEventID' "$QUEUE" \
  || { echo "FAIL: markAnswered idempotency is not durable (latest-state-only guard — recovered answers re-record forever)"; fail=1; }

# Layer 2: origin preservation in the outbox entry type and retry path.
grep -q 'export type PendingAnswerEntry' "$CONSOLE" \
  || { echo "FAIL: PendingAnswerEntry origin type missing from console.ts"; fail=1; }
grep -q 'storedReplyEventID' "$CONSOLE" \
  || { echo "FAIL: retry path does not restore the original replyEventID"; fail=1; }
grep -q 'storedChannelID' "$CONSOLE" \
  || { echo "FAIL: retry path does not restore the original channelID"; fail=1; }

# Layer 3: stale recovered answer dropped on re-decide.
grep -q '_stale' "$CONSOLE" \
  || { echo "FAIL: stale-drop-on-re-decide missing from console.ts (retry loop never terminates)"; fail=1; }

# Behavioral coverage must remain registered (guards against silent deletion).
for name in \
  'retry preserves the original channelID and replyEventID of a structured outbox entry' \
  'legacy string outbox entries fall back to console/recovered_ identity' \
  're-decide on a recovered answer drops the stale entry and re-escalates once, not forever'; do
  grep -Fq "$name" "$TESTFILE" \
    || { echo "FAIL: behavioral case missing from beacon-reply-integrity.test.ts: $name"; fail=1; }
done

test "$fail" -eq 0 || exit 1
echo "[reply-integrity-gate] PASS (durable idempotency + origin preservation + stale-drop; 3 behavioral cases registered)"
