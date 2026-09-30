#!/usr/bin/env bash
# Memory snapshot, run by opencode-continuation-checkpoint.service
# (every ~5 min) via ExecStartPost drop-in. One line per run in
# ~/.local/state/omo-mem.log. Logging only — no notifications.
# (2026-10-01: notify path removed at operator request; it misfired due to a
# baseline-parsing bug and spammed the desktop. Data stays for zram sizing.)
set -u
LOG="$HOME/.local/state/omo-mem.log"

mem_avail=$(awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo)
swap_used=$(awk '/SwapTotal/{t=$2} /SwapFree/{f=$2} END{print int((t-f)/1024)}' /proc/meminfo)
zram_used=$(zramctl --output DATA --noheadings 2>/dev/null | awk '{s+=$1} END{print int(s/1048576)}')
psi_some=$(awk '/some avg10/{print int($2)}' /proc/pressure/memory)
psi_full=$(awk '/full avg10/{print int($2)}' /proc/pressure/memory)

printf '%s mem_avail=%sM swap_used=%sM zram=%sM psi_some=%s psi_full=%s\n' \
    "$(date -Is)" "$mem_avail" "$swap_used" "$zram_used" "$psi_some" "$psi_full" >> "$LOG"
