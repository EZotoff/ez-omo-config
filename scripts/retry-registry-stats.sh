#!/usr/bin/env bash
# retry-registry-stats.sh — per-rule fire counts + last-fired timestamps from retry-plugin.log
# Usage: retry-registry-stats.sh [logfile]
#   logfile defaults to ~/.config/opencode/retry-plugin.log
# Exit 0 on success, 1 on missing/empty log.
set -euo pipefail

LOG="${1:-$HOME/.config/opencode/retry-plugin.log}"

if [[ ! -r "$LOG" ]]; then
  echo "error: log not readable: $LOG" >&2
  exit 1
fi

# Matched-error events: 'Error matched rule "<id>": ...' (matcher path)
grep -o 'Error matched rule "[^"]*"' "$LOG" 2>/dev/null \
  | sed 's/Error matched rule "//; s/"$//' \
  | sort | uniq -c | sort -rn > /tmp/retry-stats-matched.$$

# Empty-response events: 'Empty-response retry N/M for "<id>" ...' — count
# dispatched retries only to avoid double-counting the schedule+dispatch lines.
grep 'Dispatched empty-response retry' "$LOG" 2>/dev/null \
  | grep -o 'for "[^"]*"' | sed 's/for "//; s/"$//' \
  | sort | uniq -c | sort -rn > /tmp/retry-stats-empty.$$

# Last-fired per rule (first timestamp of the last matching line, both paths)
{
  grep 'Error matched rule\|Dispatched empty-response retry' "$LOG" 2>/dev/null
} | awk '
  match($0, /^\[[^]]+\]/) { ts = substr($0, 2, RLENGTH - 2) }
  match($0, /rule "[^"]+"/)  { id = substr($0, RSTART+6, RLENGTH-7); last[id] = ts }
  match($0, /for "[^"]+"/) && $0 ~ /empty-response/ { id = substr($0, RSTART+5, RLENGTH-6); last[id] = ts }
  END { for (id in last) print id, last[id] }
' | sort > /tmp/retry-stats-last.$$

echo "=== per-rule fire counts (97d+ log window: $(head -1 "$LOG" | grep -o '^\[[^]]*]' | tr -d '[]') .. $(tail -1 "$LOG" | grep -o '^\[[^]]*]' | tr -d '[]')) ==="
echo "--- matcher path (Error matched rule) ---"
cat /tmp/retry-stats-matched.$$ || true
echo "--- empty-response path (Dispatched empty-response retry) ---"
cat /tmp/retry-stats-empty.$$ || true
echo "--- last fired ---"
cat /tmp/retry-stats-last.$$ || true

rm -f /tmp/retry-stats-matched.$$ /tmp/retry-stats-empty.$$ /tmp/retry-stats-last.$$
