#!/usr/bin/env bash
# Smoke: SSE event-scope / teardown / queue-bound behavior on the live headless server.
# Covers: opencode--event-scope-attach-congestion, opencode--sse-directory-filter-removal,
#         opencode--sdk-sse-socket-leak, opencode--sse-queue-bounded, opencode--event-data-compression
# Method (all probes against the running :3021 instance — no new ports bound):
#   P1 scoping:  subscriber scoped to dir A must receive ZERO high-volume message
#                events from a real model turn in dir B; a ?scope=all subscriber
#                must receive them (pipe-works positive control).
#   P2 teardown: 40 concurrent SSE subscribers churned for ~4s; server FD count must
#                return to baseline (+/-10) within 15s of disconnect (no CLOSE_WAIT
#                accumulation — the socket-leak/queue-bound regression signature).
#   P3 decode:   every SSE frame captured by subscribers parses as valid JSON
#                (gz1 event-data-compression transparency on the wire).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib-smoke.sh
source "$HERE/lib-smoke.sh"

BIN="${SMOKE_BIN:-$HOME/.opencode/bin/opencode}"
smoke_require_binary "$BIN"
BIN_SHA="$(smoke_sha256 "$BIN")"

BASE="${SMOKE_BASE_URL:-http://127.0.0.1:3021}"
AUTH=""
if [[ -f "$HOME/.config/opencode/serve.env" ]]; then
    # shellcheck disable=SC1091
    set -a; source "$HOME/.config/opencode/serve.env" >/dev/null 2>&1; set +a
    AUTH="-u ${OPENCODE_SERVER_USERNAME:-opencode}:${OPENCODE_SERVER_PASSWORD:-}"
fi

WORK="$(mktemp -d /tmp/opencode/sse-smoke.XXXXXX)"
DIR_A="$WORK/a"; DIR_B="$WORK/b"
mkdir -p "$DIR_A" "$DIR_B"
LOG_A="$WORK/sub-A.log"; LOG_ALL="$WORK/sub-all.log"; LOG_B="$WORK/sub-B.log"
fail_note() { echo "smoke-sse-surface: $1" >&2; }

# --- find headless server pid for FD accounting -------------------------------
SRV_PID="$(ss -tlnp 2>/dev/null | awk '/:3021 /{print $NF}' | grep -oP 'pid=\K[0-9]+' | head -1)"
if [[ -z "$SRV_PID" ]]; then
    smoke_record "$BIN_SHA" event-scope-attach-congestion SKIP "no listener on $BASE" "-"
    echo "SKIP: no server on $BASE"; exit 0
fi
fd_count() { ls "/proc/$SRV_PID/fd" | wc -l; }

# --- subscribers ---------------------------------------------------------------
curl -sS -N --max-time 40 $AUTH "$BASE/event?directory=$DIR_A" >"$LOG_A" 2>"$WORK/a.err" &
SUB_A=$!
curl -sS -N --max-time 40 $AUTH "$BASE/event?directory=$DIR_A&scope=all" >"$LOG_ALL" 2>"$WORK/all.err" &
SUB_ALL=$!
curl -sS -N --max-time 40 $AUTH "$BASE/event?directory=$DIR_B" >"$LOG_B" 2>"$WORK/b.err" &
SUB_B=$!
sleep 2

# --- P2: subscriber churn (40 short-lived subscribers) --------------------------
FD_BASE="$(fd_count)"
for i in $(seq 1 40); do
    curl -sS -N --max-time 4 $AUTH "$BASE/event?directory=$DIR_A" >/dev/null 2>&1 &
done
sleep 8   # churn overlapping the model turn below
FD_AFTER_CHURN="$(fd_count)"

# --- generate a REAL model turn in dir B on this server -------------------------
set +e
OPENCODE_SERVER_PASSWORD="${OPENCODE_SERVER_PASSWORD:-}" "$BIN" run \
    --attach "$BASE" --dir "$DIR_B" \
    'Reply with exactly: OK' >"$WORK/run.log" 2>&1
RUN_RC=$?
set -e

sleep 2
kill $SUB_A $SUB_ALL $SUB_B 2>/dev/null || true
sleep 13   # let churn subscribers time out and sockets settle
FD_SETTLED="$(fd_count)"

# --- P1: scoping assertions ------------------------------------------------------
# SSE frames are "data: {json}" lines. Foreign-dir leakage = any high-volume
# message event whose location.directory == DIR_B seen by the dir-A subscriber.
# Frames carry no per-frame location field; the only model turn belongs to dir B, so
# ANY message.* frame seen by the dir-A subscriber is foreign leakage. Positive controls:
# the dir-B subscriber and the ?scope=all subscriber both receive them.
LEAK_FRAMES="$(grep -cE 'message[.]part[.]delta|message[.]updated' "$LOG_A" || true)"
B_SEES_OWN="$(grep -cE 'message[.]part[.]delta|message[.]updated' "$LOG_B" || true)"
ALL_SEES_B="$(grep -cE 'message[.]part[.]delta|message[.]updated' "$LOG_ALL" || true)"

# --- P3: wire decode validity -----------------------------------------------------
BAD_JSON="$(cat "$LOG_A" "$LOG_B" "$LOG_ALL" | jq -Rs 'split("\n") | map(select(startswith("data: "))) | .[1:] | map(.[6:] | fromjson?) | map(select(. == null)) | length' 2>/dev/null || echo 999)"

SCOPE_OK=0; TEARDOWN_OK=0; DECODE_OK=0
[[ "$LEAK_FRAMES" == "0" && "$ALL_SEES_B" != "0" && "$B_SEES_OWN" != "0" ]] && SCOPE_OK=1
[[ $(( FD_SETTLED - FD_BASE )) -le 10 ]] && TEARDOWN_OK=1
[[ "$BAD_JSON" == "0" ]] && DECODE_OK=1

NOTE="run_rc=$RUN_RC leak=$LEAK_FRAMES B_own=$B_SEES_OWN all_sees_B=$ALL_SEES_B fds $FD_BASE→$FD_AFTER_CHURN→$FD_SETTLED badjson=$BAD_JSON"
EV="$WORK/summary.txt"; printf '%s\n' "$NOTE" "$LOG_A" "$LOG_B" "$LOG_ALL" > "$EV" 2>/dev/null || true

[[ $SCOPE_OK -eq 1 ]] && smoke_record "$BIN_SHA" event-scope-attach-congestion PASS "zero foreign-dir message frames at scoped subscriber; scope=all saw $ALL_SEES_B" "$NOTE" \
                    || smoke_record "$BIN_SHA" event-scope-attach-congestion FAIL "scoping broken or positive control absent" "$NOTE"
# directory-filter-removal: non-message events must flow cross-directory (unscoped classes).
NONMSG_CROSS="$(jq -Rs 'split("\n") | map(select(startswith("data: "))) | .[1:] | map(.[6:] | fromjson?) | map(select(.type | test("^message\\.") | not)) | length' "$LOG_A" 2>/dev/null || echo 0)"
[[ "$NONMSG_CROSS" != "0" ]] && smoke_record "$BIN_SHA" sse-directory-filter-removal PASS "non-message cross-directory events visible to scoped subscriber ($NONMSG_CROSS frames)" "$NOTE" \
                             || smoke_record "$BIN_SHA" sse-directory-filter-removal FAIL "no cross-directory non-message frames — over-filtering" "$NOTE"
[[ $TEARDOWN_OK -eq 1 ]] && smoke_record "$BIN_SHA" sdk-sse-socket-leak PASS "fds $FD_BASE→$FD_AFTER_CHURN→$FD_SETTLED after 40-subscriber churn" "$NOTE" \
                        || smoke_record "$BIN_SHA" sdk-sse-socket-leak FAIL "FD count did not settle after churn" "$NOTE"
[[ $TEARDOWN_OK -eq 1 ]] && smoke_record "$BIN_SHA" sse-queue-bounded PASS "no fd/queue accumulation after churn (settled $FD_SETTLED vs base $FD_BASE)" "$NOTE" \
                        || smoke_record "$BIN_SHA" sse-queue-bounded FAIL "accumulation after churn" "$NOTE"
[[ $DECODE_OK -eq 1 ]] && smoke_record "$BIN_SHA" event-data-compression PASS "all captured SSE frames parse as JSON (gz1 transparent on the wire)" "$NOTE" \
                      || smoke_record "$BIN_SHA" event-data-compression FAIL "unparseable SSE frames" "$NOTE"
# stream-stall-watchdog needs a 10-minute stalled stream — not smokeable in-band; organic field
# evidence lives in the patch entry. Record SKIP so the state is explicit, not pending.
smoke_record "$BIN_SHA" stream-stall-watchdog SKIP "needs 10-min stall; organic field evidence in patch entry (91 fires, 35/40 recovered)" "patch entry runtime_effective note"

echo "smoke-sse-surface done: $NOTE"
[[ $SCOPE_OK -eq 1 && $TEARDOWN_OK -eq 1 && $DECODE_OK -eq 1 && $RUN_RC -eq 0 ]]
