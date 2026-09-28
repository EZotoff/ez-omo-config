#!/usr/bin/env bash
# Regression 030: wisdom-search tokenized multi-field matching.
#
# Pre-fix matcher: whole-query case-insensitive substring on .body only, so
# multi-word natural-language queries structurally returned zero hits
# (82.7% zero-hit rate measured 2026-09-28). Post-fix: whole-query body
# substring OR any whitespace-separated term matched across title+body+tags,
# ranked by matched-term coverage.
#
# Runs fully inside a sandbox WISDOM_ROOT — never touches live stores.
set -o errexit

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SEARCH="$REPO_ROOT/scripts/wisdom/wisdom-search.sh"
TESTS_PASSED=0; TESTS_FAILED=0

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
export WISDOM_ROOT="$SANDBOX"
mkdir -p "$SANDBOX/projects"

cat > "$SANDBOX/system.jsonl" <<'EOF'
{"id":"t-title-hit","type":"gotcha","status":"active","authority":"verified","scope":"system","title":"typography","body":"loading the skill requires its SKILL.md frontmatter","tags":["web"],"quality_score":7}
{"id":"t-tag-hit","type":"pattern","status":"active","authority":"verified","scope":"system","title":"browser config","body":"set the default handler via xdg settings","tags":["browser"],"quality_score":6}
{"id":"t-body-hit","type":"fact","status":"active","authority":"verified","scope":"system","title":"unrelated","body":"retry plugin handles provider quota exhaustion","tags":["opencode"],"quality_score":5}
EOF

hit_count() {
    local n=0
    n=$(bash "$SEARCH" "$1" --no-touch --json 2>/dev/null | jq 'length' 2>/dev/null) || n=0
    printf '%s' "$n"
}

# 1. Title-term match that the body-only substring matcher could not find.
n=$(hit_count "typography skill")
if [[ "$n" -ge 1 ]]; then TESTS_PASSED=$((TESTS_PASSED+1)); else
    echo "FAIL: title-term query 'typography skill' returned $n results (want >=1)"; TESTS_FAILED=$((TESTS_FAILED+1)); fi

# 2. Tag-term match.
n=$(hit_count "browser default")
if [[ "$n" -ge 1 ]]; then TESTS_PASSED=$((TESTS_PASSED+1)); else
    echo "FAIL: tag-term query 'browser default' returned $n results (want >=1)"; TESTS_FAILED=$((TESTS_FAILED+1)); fi

# 3. Whole-query body substring still matches (old behavior preserved).
n=$(hit_count "provider quota exhaustion")
if [[ "$n" -ge 1 ]]; then TESTS_PASSED=$((TESTS_PASSED+1)); else
    echo "FAIL: whole-query body substring returned $n results (want >=1)"; TESTS_FAILED=$((TESTS_FAILED+1)); fi

# 4. Genuinely absent terms still return zero results (no false positives).
if bash "$SEARCH" zzzzabsentterm --no-touch >/dev/null 2>&1; then
    echo "FAIL: absent-term query unexpectedly returned results (want exit 1)"; TESTS_FAILED=$((TESTS_FAILED+1))
else TESTS_PASSED=$((TESTS_PASSED+1)); fi

# 5. Coverage ranking: entry matching more query terms ranks first.
first_id=$(bash "$SEARCH" "retry plugin quota" --no-touch --json 2>/dev/null | jq -r '.[0].id' 2>/dev/null) || first_id=""
if [[ "$first_id" == "t-body-hit" ]]; then TESTS_PASSED=$((TESTS_PASSED+1)); else
    echo "FAIL: coverage ranking expected t-body-hit first, got '${first_id}'"; TESTS_FAILED=$((TESTS_FAILED+1)); fi

# 6. JSON output contract intact (valid array).
if bash "$SEARCH" "retry" --no-touch --json 2>/dev/null | jq -e 'type == "array"' >/dev/null 2>&1; then
    TESTS_PASSED=$((TESTS_PASSED+1))
else echo "FAIL: --json did not emit a valid JSON array"; TESTS_FAILED=$((TESTS_FAILED+1)); fi

if [[ $TESTS_FAILED -gt 0 ]]; then exit 1; fi
echo "PASS: regression 030 (tokenized multi-field search)"
