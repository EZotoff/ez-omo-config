#!/usr/bin/env bash
# Memory snapshot + alert, run by opencode-continuation-checkpoint.service
# (every ~5 min) via ExecStartPost drop-in. One line per run in
# ~/.local/state/omo-mem.log; notify-send on PSI>20 or swap growth >2G/24h.
# No daemon: pure append + threshold check. (2026-09-30, operator-approved.)
set -u
STATE_DIR="$HOME/.local/state"
LOG="$STATE_DIR/omo-mem.log"
export DISPLAY="${DISPLAY:-:1}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/$(id -u)/bus}"

mem_avail=$(awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo)
swap_used=$(awk '/SwapTotal/{t=$2} /SwapFree/{f=$2} END{print int((t-f)/1024)}' /proc/meminfo)
zram_used=$(zramctl --output DATA --noheadings 2>/dev/null | awk '{s+=$1} END{print int(s/1048576)}')
psi_some=$(awk '/some avg10/{print int($2)}' /proc/pressure/memory)
psi_full=$(awk '/full avg10/{print int($2)}' /proc/pressure/memory)
ts=$(date -Is)

printf '%s mem_avail=%sM swap_used=%sM zram=%sM psi_some=%s psi_full=%s\n' \
    "$ts" "$mem_avail" "$swap_used" "$zram_used" "$psi_some" "$psi_full" >> "$LOG"

alert=""
# PSI pressure right now
[ "${psi_some:-0}" -gt 20 ] && alert="memory PSI some=${psi_some}%"
# swap growth >2G vs the closest sample 23-25h old
old=$(awk -v cut="$(date -d '24 hours ago' +%s)" \
      '{cmd="date -d "$1" +%s"; cmd | getline t; close(cmd); if (t<=cut) su=$4}
       END{print su+0}' "$LOG" 2>/dev/null)
[ -n "$old" ] && [ $((swap_used - old)) -gt 2048 ] && alert="swap grew $((swap_used - old))M in 24h"

if [ -n "$alert" ]; then
    notify-send -u critical -a omo-mem "OpenCode memory alert" "$alert (see $LOG)" 2>/dev/null || true
fi
