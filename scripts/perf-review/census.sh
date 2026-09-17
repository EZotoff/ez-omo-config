#!/usr/bin/env bash
# census.sh — baseline log census for the perf-review-server-plugins plan.
#
# Prints size/activity stats for the 6 config-layer plugin logs under
# $HOME/.config/opencode/ and the 2 proof-event sinks under
# $HOME/.local/share/opencode/. Missing files print "name<TAB>MISSING"
# and never abort the script (evidence capture must complete).
set -euo pipefail

LOG_DIR="$HOME/.config/opencode"
DATA_DIR="$HOME/.local/share/opencode"

for name in aspect-dynamics output-shaper skill-nudger agent-default-guard live-config-guard retry-plugin; do
  log="$LOG_DIR/$name.log"
  if [ -f "$log" ]; then
    lines=$(wc -l < "$log")
    bytes=$(stat -c%s "$log")
    mtime=$(stat -c%y "$log")
    printf '%s\t%s\t%s\t%s\n' "$name" "$lines" "$bytes" "$mtime"
  else
    printf '%s\tMISSING\n' "$name"
  fi
done

for name in aspect-dynamics skill-nudger; do
  sink="$DATA_DIR/$name/events.jsonl"
  if [ -f "$sink" ]; then
    events=$(wc -l < "$sink")
    bytes=$(stat -c%s "$sink")
    printf '%s\t%s\t%s\n' "$name" "$events" "$bytes"
  else
    printf '%s\tMISSING\n' "$name"
  fi
done
