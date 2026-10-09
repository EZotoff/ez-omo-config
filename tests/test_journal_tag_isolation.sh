#!/usr/bin/env bash
# Journal tag isolation (design 2, L1; plan M4 TODO 23).
#
# Contract: journal_alert() honors CONTINUATION_JOURNAL_TAG. With the test tag
# set, the alert lands under `restart-continuation-test` and the production tag
# `restart-continuation` (the namespace the supervisor journal->ledger bridge
# tails) receives NO entry for the test unit. This is the primary defense
# against regression-test alerts polluting the production ledger.
#
# Self-contained: no server needed — a closed port makes hook-snapshot fail its
# preflight fast and emit a `preflight_failed` alert. Test-local XDG_STATE_DIR.
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/helpers.sh"

SCRIPT_UNDER_TEST="$(cd "$(dirname "$0")/.." && pwd)/scripts/restart-with-continuation.sh"
TESTUNIT="tag-isolation-test.service"
PROD_TAG="restart-continuation"
TEST_TAG="restart-continuation-test"

command -v journalctl >/dev/null 2>&1 || { echo "SKIP: journalctl not available"; exit 0; }
journalctl --user -n 0 >/dev/null 2>&1 || { echo "SKIP: user journal not available"; exit 0; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/opencode/journal-tag-isolation.XXXXXX")"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

ENVFILE="$WORK/test.env"
printf 'OPENCODE_SERVER_PASSWORD=regression-test-pass\n' > "$ENVFILE"

# A closed port: preflight fails immediately (connection refused), no server.
PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')"
URL="http://127.0.0.1:$PORT"

JOURNAL_SINCE="$(date '+%Y-%m-%d %H:%M:%S')"

set +e
CONTINUATION_JOURNAL_TAG="$TEST_TAG" XDG_STATE_DIR="$WORK/state" timeout 20 bash "$SCRIPT_UNDER_TEST" \
    hook-snapshot "$TESTUNIT" "$URL" "$ENVFILE" > "$WORK/hook.out" 2>&1
set -e
sleep 1

# (a) the test tag receives the alert for the test unit.
if journalctl --user -t "$TEST_TAG" --since "$JOURNAL_SINCE" 2>/dev/null | grep -q "$TESTUNIT"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "PASS (a): test tag '$TEST_TAG' received the alert for $TESTUNIT"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "FAIL (a): no '$TEST_TAG' journal entry for $TESTUNIT since $JOURNAL_SINCE"
fi

# (b) the production tag stays clean for the test unit.
if journalctl --user -t "$PROD_TAG" --since "$JOURNAL_SINCE" 2>/dev/null | grep -q "$TESTUNIT"; then
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "FAIL (b): production tag '$PROD_TAG' received a test-unit alert (namespace leak)"
else
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "PASS (b): production tag '$PROD_TAG' clean for $TESTUNIT"
fi

if [[ $TESTS_FAILED -gt 0 ]]; then
    echo "FAILURE: journal tag isolation broken (see $0)"
    exit 1
fi
echo "PASS: CONTINUATION_JOURNAL_TAG isolates test alerts from the production namespace"
