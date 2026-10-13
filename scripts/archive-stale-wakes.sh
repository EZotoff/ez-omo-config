#!/usr/bin/env bash
# archive-stale-wakes.sh — one-shot mitigation for the leaked wake backlog.
#
# Moves NON-TERMINAL wake-journal files whose CONTENT age is >= --max-age-seconds
# (default 21600 = 6h) into a per-run timestamped `archived-<stamp>/` subdir
# beside them. NEVER deletes. Dry-run by default; pass --apply to move.
#
# Freshness is judged by the timestamps recorded INSIDE each wake
# (firstDispatchedAt/dispatchedAt/claimedAt/history[-1].at, ms-epoch), never by
# file mtime — the 2026-10-13 incident showed an unidentified writer can
# mass-refresh mtimes, making months-old leftovers look brand new. A wake with
# no readable content timestamp cannot prove staleness and is left untouched.
#
# Usage:
#   scripts/archive-stale-wakes.sh [--apply] [--max-age-seconds N]
#
# Exit 0 even when nothing qualifies.
set -euo pipefail

APPLY=false
MAX_AGE=21600
while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) APPLY=true ;;
    --max-age-seconds) MAX_AGE="${2:?--max-age-seconds needs a value}"; shift ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

MODE="dry-run"
if $APPLY; then MODE="apply"; fi
STAMP="$(date +%Y%m%d-%H%M%S)"

# --- wake-dir discovery (dedup, /tmp excluded) ------------------------------
declare -A seen=()
wake_dirs=()
add_dir() {
  local w="$1"
  [[ -d "$w" ]] || return 0
  [[ -n "${seen[$w]:-}" ]] && return 0
  seen[$w]=1
  wake_dirs+=("$w")
}

db="$HOME/.local/share/opencode/opencode.db"
if [[ -f "$db" ]]; then
  while IFS= read -r dir; do
    [[ -n "$dir" ]] || continue
    add_dir "$dir/.omo/run-continuation/wakes"
  done < <(python3 - "$db" <<'PYEOF'
import sqlite3, sys
con = sqlite3.connect("file:%s?mode=ro" % sys.argv[1], uri=True)
for (d,) in con.execute(
        "select distinct directory from session "
        "where time_archived is null and directory != '' "
        "and directory not like '/tmp/%'"):
    print(d)
PYEOF
)
fi

for w in "$HOME"/*/.omo/run-continuation/wakes "$HOME"/*/*/.omo/run-continuation/wakes; do
  add_dir "$w"
done

# --- scan + archive ---------------------------------------------------------
archived=0; skipped_malformed=0; scanned=0
for d in "${wake_dirs[@]}"; do
  # python prints newline-delimited TAB-separated candidate records
  # (src, sid, state, age) then a "#SUMMARY\t<scanned>\t<malformed>" line.
  # bash performs the mv — no string-interpolated Python source.
  while IFS=$'\t' read -r src sid state age; do
    if [[ "$src" == "#SUMMARY" ]]; then
      scanned=$((scanned + sid))
      skipped_malformed=$((skipped_malformed + state))
      continue
    fi
    [[ -n "$src" ]] || continue
    dst_dir="$d/archived-$STAMP"
    dst="$dst_dir/$(basename "$src")"
    if $APPLY; then
      mkdir -p "$dst_dir"
      mv "$src" "$dst"
      printf 'ARCHIVE %s -> %s sid=%s state=%s age=%ss\n' "$src" "$dst" "$sid" "$state" "$age"
      archived=$((archived + 1))
    else
      printf '[dry-run] would archive %s -> %s sid=%s state=%s age=%ss\n' "$src" "$dst" "$sid" "$state" "$age"
    fi
  done < <(python3 - "$d" "$MAX_AGE" <<'PYEOF'
import glob, json, os, sys, time
d = sys.argv[1]
max_age = float(sys.argv[2])
nonterminal = {'queued', 'dispatching', 'dispatched-awaiting-output'}

def age_basis(w):
    cands = []
    for k in ('firstDispatchedAt', 'dispatchedAt', 'claimedAt'):
        v = w.get(k)
        if isinstance(v, (int, float)) and v > 0:
            cands.append(v / 1000.0)
    hist = w.get('history')
    if isinstance(hist, list) and hist and isinstance(hist[-1], dict):
        v = hist[-1].get('at')
        if isinstance(v, (int, float)) and v > 0:
            cands.append(v / 1000.0)
    return max(cands) if cands else None

now = time.time()
scanned = malformed = 0
for wf in sorted(glob.glob(os.path.join(d, '*.json'))):
    scanned += 1
    try:
        w = json.load(open(wf))
    except (ValueError, OSError):
        malformed += 1
        continue
    if w.get('state') not in nonterminal:
        continue
    ab = age_basis(w)
    if ab is None:
        continue
    age = now - ab
    if age < max_age:
        continue
    print("%s\t%s\t%s\t%d" % (wf, w.get('sessionID') or '', w.get('state'), int(age)))
print("#SUMMARY\t%d\t%d" % (scanned, malformed))
PYEOF
)
done

printf 'archived=%d skipped_malformed=%d scanned=%d mode=%s\n' \
  "$archived" "$skipped_malformed" "$scanned" "$MODE"
exit 0
