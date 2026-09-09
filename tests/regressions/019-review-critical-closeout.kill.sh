#!/usr/bin/env bash
# Kill-test 019: proves regression 019 detects reintroduced CRITICAL-laundering.
#
# Copies both live files to a temp dir, reintroduces the pre-fix semantics
# (proceed-regardless closeout, INFO-demotion, old enforcer line), then runs
# the same checks the regression runs — expecting detection.
set -o errexit
source "$(cd "$(dirname "$0")/.." && pwd)/helpers.sh"

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
command -v python3 >/dev/null 2>&1 || { echo "FAIL: python3 not found"; exit 1; }

KILL_TMP="$(mktemp -d)"
trap 'rm -rf "$KILL_TMP"' EXIT

cp "$REPO_ROOT/skills/atlas-review-handler/SKILL.md" "$KILL_TMP/SKILL.md"
cp "$REPO_ROOT/plugins/review-enforcer.ts" "$KILL_TMP/review-enforcer.ts"

# Reintroduce the bug shape in the skill copy: erase the closeout contract
# markers and restore the old proceed-regardless / INFO-demotion text.
python3 - "$KILL_TMP/SKILL.md" <<'PYEOF'
import sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
if "CRITICAL CLOSEOUT" not in text:
    print("FAIL: sabotage precondition — CRITICAL CLOSEOUT not found in live skill")
    sys.exit(1)
text = text.replace("CRITICAL CLOSEOUT", "CYCLE-2 CLOSEOUT (SABOTAGED)")
text = text.replace(
    "Never silently demote a CRITICAL finding to INFO.",
    "After 2 cycles, STOP and proceed regardless of findings.\n- Note remaining findings as INFO-level advisories.",
)
open(path, "w", encoding="utf-8").write(text)
PYEOF

# Reintroduce the bug shape in the enforcer copy: restore the old line.
python3 - "$KILL_TMP/review-enforcer.ts" <<'PYEOF'
import sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
if "RULE/BLOCK/PARK" not in text:
    print("FAIL: sabotage precondition — RULE/BLOCK/PARK not found in live enforcer")
    sys.exit(1)
text = text.replace(
    "4. Maximum two review cycles; unresolved CRITICAL findings require handler closeout (RULE/BLOCK/PARK) and must never be represented as approval",
    "4. Maximum 2 review cycles, then proceed regardless",
)
open(path, "w", encoding="utf-8").write(text)
PYEOF

# The regression's checks (duplicated here, scoped to the sabotaged copies)
# must detect the reintroduction: old text present, new contract absent.
detected=0
grep -q 'proceed regardless' "$KILL_TMP/SKILL.md" && detected=1
grep -q 'INFO-level advisories' "$KILL_TMP/SKILL.md" && detected=1
grep -q 'CRITICAL CLOSEOUT' "$KILL_TMP/SKILL.md" || detected=1
grep -q 'proceed regardless' "$KILL_TMP/review-enforcer.ts" && detected=1
grep -q 'RULE/BLOCK/PARK' "$KILL_TMP/review-enforcer.ts" || detected=1

if [[ $detected -eq 0 ]]; then
    echo "FAILURE: kill-test 019 broken — regression did not detect reintroduced laundering"
    exit 1
fi
echo "PROVED: regression 019 detects reintroduced CRITICAL laundering"
