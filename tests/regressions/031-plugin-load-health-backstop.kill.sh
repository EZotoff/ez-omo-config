#!/usr/bin/env bash
# Kill variant for regression 031: break the detection filter and confirm the
# test FAILS. Kill method: replace the core grep pattern so real plugin-load
# failures match nothing — the silent-outage failure mode the backstop exists
# to prevent.
set -o errexit
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/check-plugin-load-health.sh"
TEST="$HERE/031-plugin-load-health-backstop.sh"

[[ -f "$SCRIPT" ]] || { echo "KILL-SKIP: script missing"; exit 0; }
cp "$SCRIPT" "$SCRIPT.kill-bak"
trap 'mv "$SCRIPT.kill-bak" "$SCRIPT"' EXIT
# Neuter the failure-detection grep: nothing will ever match
sed -i 's/grep -a "failed to load plugin"/grep -a "__never_matches__"/' "$SCRIPT"

if bash "$TEST" >/dev/null 2>&1; then
  echo "KILL-FAIL: 031 still passed with detection neutered"
  exit 1
fi
echo "KILL-PASS: 031 fails when detection is neutered"
exit 0
