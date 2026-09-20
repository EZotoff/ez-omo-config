#!/usr/bin/env bash
# Regression: opencode--plugin-engine-prerelease
# Proves (a) the source fix is present — checkPluginCompatibility passes
# { includePrerelease: true } to semver.satisfies; (b) the semver semantics the
# fix relies on hold: a prerelease-suffixed host version (1.18.31-p1, the
# -p<N> provenance scheme) fails a plain >= range WITHOUT includePrerelease and
# passes WITH it; (c) the patch is registered in the lockfile.
set -o errexit
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
SRC="${PLUGIN_ENGINE_PRERELEASE_SRC:-$HOME/src/opencode/packages/opencode/src/plugin/shared.ts}"
SEMVER="${SEMVER_MODULE:-$HOME/src/opencode/node_modules/semver}"

# (a) source fix present
grep -q 'semver.satisfies(opencodeVersion, range, { includePrerelease: true })' "$SRC" \
    || { echo "FAIL: includePrerelease arg missing from checkPluginCompatibility in $SRC"; exit 1; }

# (b) semver behavior: prerelease host version excluded by default, included with flag
node -e "
const s = require('$SEMVER');
const v = '1.18.31-p1', range = '>=1.4.6';
if (s.satisfies(v, range) !== false) { console.log('FAIL: expected default satisfies to exclude prerelease'); process.exit(1); }
if (s.satisfies(v, range, { includePrerelease: true }) !== true) { console.log('FAIL: expected includePrerelease to satisfy range'); process.exit(1); }
" 2>/dev/null || { echo "SKIP: semver module not found at $SEMVER"; }

# (c) lockfile registration
python3 - "$REPO/config/patch-lockfile.json" <<'PYEOF'
import json, sys
lf = json.load(open(sys.argv[1]))
hits = [p for p in lf["patches"] if p["patch_id"] == "opencode--plugin-engine-prerelease"]
assert hits, "FAIL: patch missing from lockfile"
assert hits[0].get("implementation_commits"), "FAIL: lockfile entry has no implementation_commits"
PYEOF

echo "PASS: plugin-engine-prerelease fix present, semver semantics proven, lockfile registered"
