#!/usr/bin/env bash
# Regression: archive-stale-wakes.sh archives by CONTENT age, never mtime.
#
# Contract (plan: continuation-idle-kickstart-fix T3): the one-shot archiver
# moves NON-TERMINAL wakes whose content age >= --max-age-seconds into a
# timestamped archived-*/ subdir (never deletes). Dry-run is the default and
# moves nothing. Terminal-state and timestamp-less wakes are never moved.
# SCRIPT env override lets the paired .kill.sh point at a bugged copy.
set -uo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/helpers.sh"

SCRIPT="${SCRIPT:-$(cd "$(dirname "$0")/../.." && pwd)/scripts/archive-stale-wakes.sh}"
REAL_HOME="$HOME"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

SCRATCH="$(mktemp -d "${REAL_HOME:-$HOME}/.cache/cont-arch.XXXXXX")"
export SCRATCH
cleanup() { rm -rf "$SCRATCH"; }
trap cleanup EXIT

export HOME="$SCRATCH/home"
WAKES="$HOME/proj/.omo/run-continuation/wakes"
mkdir -p "$WAKES"

NOW_S="$(date +%s)"
STALE_MS="$(( (NOW_S - 7*3600) * 1000 ))"   # 7h old content
FRESH_MS="$(( (NOW_S - 3600) * 1000 ))"     # 1h old content
ANCIENT_MS="$(( (NOW_S - 30*86400) * 1000 ))"

# (A) content-stale, non-terminal, mtime FRESH (the bug shape)
printf '%s\n' "{\"sessionID\":\"sid-stale\",\"state\":\"dispatched-awaiting-output\",\"title\":\"S\",\"firstDispatchedAt\":$STALE_MS}" > "$WAKES/a-stale.json"
touch "$WAKES/a-stale.json"
# (B) fresh content, non-terminal
printf '%s\n' "{\"sessionID\":\"sid-fresh\",\"state\":\"queued\",\"title\":\"F\",\"firstDispatchedAt\":$FRESH_MS}" > "$WAKES/b-fresh.json"
# (C) terminal state, ancient content
printf '%s\n' "{\"sessionID\":\"sid-term\",\"state\":\"consumed\",\"title\":\"T\",\"firstDispatchedAt\":$ANCIENT_MS}" > "$WAKES/c-term.json"
# (D) garbage
printf 'not json {{{' > "$WAKES/d-garbage.json"

# --- dry-run: lists the stale wake, moves nothing ---------------------------
out="$(bash "$SCRIPT" 2>&1)"; rc=$?
if [[ $rc -eq 0 ]] && grep -q 'a-stale.json' <<<"$out" && grep -q 'would archive' <<<"$out"; then
  ok "dry-run lists the content-stale wake"
else
  bad "dry-run did not list the stale wake (rc=$rc)"
fi
if [[ -f "$WAKES/a-stale.json" && -f "$WAKES/b-fresh.json" && -f "$WAKES/c-term.json" ]]; then
  ok "dry-run moved nothing"
else
  bad "dry-run moved files"
fi
if ! grep -q 'b-fresh.json' <<<"$out" && ! grep -q 'c-term.json' <<<"$out"; then
  ok "fresh + terminal wakes not listed"
else
  bad "fresh/terminal wake wrongly listed"
fi
if grep -q 'skipped_malformed=1' <<<"$out"; then
  ok "garbage .json counted as skipped_malformed"
else
  bad "garbage .json not counted (summary: $(grep '^archived=' <<<"$out"))"
fi

# --- apply: moves the stale wake under archived-*/, leaves the rest ---------
out2="$(bash "$SCRIPT" --apply 2>&1)"; rc2=$?
if [[ $rc2 -eq 0 ]] && [[ ! -f "$WAKES/a-stale.json" ]] \
   && compgen -G "$WAKES/archived-*/a-stale.json" >/dev/null; then
  ok "--apply moved the stale wake under archived-*/ (original gone)"
else
  bad "--apply did not archive the stale wake (rc=$rc2)"
fi
if [[ -f "$WAKES/b-fresh.json" && -f "$WAKES/c-term.json" && -f "$WAKES/d-garbage.json" ]]; then
  ok "fresh, terminal, and garbage wakes untouched by --apply"
else
  bad "non-candidates were moved by --apply"
fi

echo "=========================================="
echo "archive-stale-wakes: $PASS passed | $FAIL failed"
echo "=========================================="
[[ $FAIL -eq 0 ]]
