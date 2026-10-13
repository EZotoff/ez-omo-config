#!/usr/bin/env bash
# Kill-proof for archive-stale-wakes.sh.
#
# Copies the archiver, sed-swaps the content-age predicate back to the buggy
# mtime predicate, and re-runs the dry-run against the same fixture. The
# content-stale/mtime-fresh wake MUST NOT be selected by the bugged copy —
# proving the regression test's assertion actually detects the bug.
set -uo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/helpers.sh"

REAL_SCRIPT="$(cd "$(dirname "$0")/../.." && pwd)/scripts/archive-stale-wakes.sh"
REAL_HOME="$HOME"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

SCRATCH="$(mktemp -d "${REAL_HOME:-$HOME}/.cache/cont-arch-kill.XXXXXX")"
export SCRATCH
cleanup() { rm -rf "$SCRATCH"; }
trap cleanup EXIT

BUGGED="$SCRATCH/archive-stale-wakes-bugged.sh"
sed 's/^    ab = age_basis(w)$/    ab = os.path.getmtime(wf)/' "$REAL_SCRIPT" > "$BUGGED"
if ! grep -q 'ab = os.path.getmtime(wf)' "$BUGGED"; then
  bad "sed did not revert the content predicate in the bugged copy"
  echo "kill-proof: $PASS passed | $FAIL failed"; exit 1
fi

export HOME="$SCRATCH/home"
WAKES="$HOME/proj/.omo/run-continuation/wakes"
mkdir -p "$WAKES"
NOW_S="$(date +%s)"
STALE_MS="$(( (NOW_S - 7*3600) * 1000 ))"
printf '%s\n' "{\"sessionID\":\"sid-stale\",\"state\":\"dispatched-awaiting-output\",\"title\":\"S\",\"firstDispatchedAt\":$STALE_MS}" > "$WAKES/a-stale.json"
touch "$WAKES/a-stale.json"   # mtime fresh — the bug shape

out="$(bash "$BUGGED" 2>&1)" || true
if ! grep -q 'a-stale.json' <<<"$out"; then
  ok "bugged (mtime-gated) copy does NOT select the content-stale wake — test assertion is sensitive"
else
  bad "bugged copy still selected the stale wake — kill-proof cannot detect the bug"
fi

echo "=========================================="
echo "archive-stale-wakes.kill: $PASS passed | $FAIL failed"
echo "=========================================="
[[ $FAIL -eq 0 ]]
