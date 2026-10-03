#!/usr/bin/env bash
# 032-event-data-compression.kill.sh — kill check for the event-data-compression
# regression pair. Runs the .sh against the UNPATCHED (pre-codec) binary and
# EXPECTS it to FAIL (no gz1: rows can appear). If the .sh passes on an
# unpatched binary, the detector detects nothing and this kill check fails.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SH="$HERE/032-event-data-compression.sh"

UNPATCHED="${UNPATCHED_BIN:-}"
if [[ -z "$UNPATCHED" ]]; then
    # Newest pre-codec backup (p2 lineage, before event-data-compression).
    UNPATCHED="$(ls -t "$HOME"/.opencode/bin/opencode.backup-1.18.31-p2-* 2>/dev/null | head -1 || true)"
fi
[[ -n "$UNPATCHED" && -x "$UNPATCHED" ]] || { echo "SKIP: no unpatched backup binary found (set UNPATCHED_BIN)"; exit 0; }

if OPENCODE_BIN="$UNPATCHED" OPENCODE_BIN_SET=1 bash "$SH" >/dev/null 2>&1; then
    echo "KILL-FAIL: regression PASSED on unpatched binary ($UNPATCHED) — detector is blind"
    exit 1
fi
echo "KILL-PASS: regression FAILS on unpatched binary ($UNPATCHED) as expected"
exit 0
