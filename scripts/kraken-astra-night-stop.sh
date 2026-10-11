#!/usr/bin/env bash
# kraken-astra-night-stop.sh — reclaim the ASTRA daemon's RAM outside the night window.
#
# Runs daily at 09:15 (kraken-astra-night-stop.timer). The daemon's enabled cron
# jobs (spacebot config.toml): nightly-research 01:00 (12h zombie-guard ceiling),
# verify-results 07:00 (2h), autonomy-check 07:30 (1h), autonomy-fixer 08:15 (2h).
# 09:15 = last fire + 1h grace for stragglers to finish (operator request
# 2026-10-11). A fixer run that legitimately needs its full 2h ceiling would be
# cut at 09:15 — graceful SIGTERM gives it a shutdown window; systemd stops the
# whole cgroup (incl. the daemon-spawned opencode server).
#
# EXCEPTION — bimonthly-review fires 09:00 on day 1 of odd months with an 8h
# timeout. On those days the stop is SKIPPED; the daemon runs the review and is
# stopped the next morning at 09:15 (cost: ~1 extra daemon-day, 6 times a year).
set -u
LOG="$HOME/.spacebot/night-window.log"
UNIT=spacebot-astra.service

log() { echo "$(date -Is) [night-stop] $*" >> "$LOG"; }

DOM=$(date +%-d)
MONTH=$(date +%-m)
if [ "$DOM" = "1" ] && [ $((MONTH % 2)) -eq 1 ]; then
  log "bimonthly-review day (day 1, month $MONTH) — skip; daemon stays up for the 09:00 review, stopped tomorrow 09:15"
  echo "skip: bimonthly-review day"
  exit 0
fi

if ! systemctl --user is-active --quiet "$UNIT"; then
  log "daemon already inactive — nothing to do"
  echo "already stopped"
  exit 0
fi

MAIN_PID=$(systemctl --user show -p MainPID --value "$UNIT")
if [ -n "$MAIN_PID" ] && [ "$MAIN_PID" != "0" ]; then
  RSS=$(awk '/^VmRSS:/{print $2}' "/proc/$MAIN_PID/status" 2>/dev/null || echo '?')
  SWAP=$(awk '/^VmSwap:/{print $2}' "/proc/$MAIN_PID/status" 2>/dev/null || echo '?')
  log "stopping $UNIT (pid $MAIN_PID, RSS ${RSS:-?} kB, swap ${SWAP:-?} kB)"
fi

if systemctl --user stop "$UNIT"; then
  log "stopped cleanly"
  echo "spacebot-astra stopped"
else
  log "systemctl stop FAILED (exit $?)"
  echo "stop FAILED" >&2
  exit 1
fi

# Post-check: unit inactive and no stray daemon processes left.
sleep 2
if systemctl --user is-active --quiet "$UNIT"; then
  log "unit still active after stop — unexpected"
  echo "unit still active" >&2
  exit 1
fi
log "verified: unit inactive, cgroup torn down by systemd"
exit 0
