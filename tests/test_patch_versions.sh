#!/usr/bin/env bash
# test_patch_versions.sh — drift gate: fail on unresolved VERSION-DRIFT
#
# This is the CLOSED LOOP between "binary upgraded" and "patches reconciled."
# After any opencode binary swap, dep_version fields go stale. This test fails
# until every active patch has been reconciled: either dep_version bumped to
# match the live binary (runtime_effective: true) or runtime_effective: false
# with a justification (ACKNOWLEDGED-DRIFT).
#
# Only VERSION-DRIFT causes failure. STALE (pattern not found in OMO dist),
# MISSING-TARGET (OMO config path), and ACKNOWLEDGED-DRIFT (known-ineffective)
# do NOT fail — they have legitimate reasons for not matching.
#
# The review-enforcer plugin consumes test output, so unresolved drift blocks
# the merge. This forces patch reconciliation to happen as part of the SAME
# commit/PR as the binary upgrade, not as a forgotten follow-up.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=== Patch Version Drift Gate ==="
echo "Checking all active patches against live binary version"
echo ""

# Run verifier in JSON mode and extract drift counts
output="$(bash "$REPO_ROOT/scripts/verify-live-patches.sh" --json 2>/dev/null || true)"

if [[ -z "$output" ]]; then
    echo "FAIL: verify-live-patches.sh produced no JSON output"
    exit 1
fi

read -r drift_count acknowledged_count <<< "$(echo "$output" | python3 -c '
import json, sys
s = json.load(sys.stdin)["summary"]
print(s["version_drift"], s["acknowledged_drift"])
')"

if (( drift_count > 0 )); then
    echo "FAIL: $drift_count patch(es) have unresolved VERSION-DRIFT"
    echo ""
    echo "These patches have dep_version not matching the live binary AND no"
    echo "runtime_effective: false flag. Resolve by EITHER:"
    echo "  1. Verifying the patch is effective on the new binary → bump dep_version"
    echo "     and set runtime_effective: true"
    echo "  2. Confirming the patch is ineffective → set runtime_effective: false"
    echo "     with a justification (becomes ACKNOWLEDGED-DRIFT, exempt from this gate)"
    echo ""
    echo "Run: bash scripts/verify-live-patches.sh  (for details)"
    exit 1
fi

if (( acknowledged_count > 0 )); then
    echo "PASS: 0 unresolved version-drift ($acknowledged_count acknowledged-drift exempt)"
else
    echo "PASS: 0 version-drift, all patches reconciled"
fi
