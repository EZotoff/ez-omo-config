#!/usr/bin/env bash
# Kill-test 030: proves regression 030 detects the reverted (pre-fix) matcher.
#
# Reintroduces the old shape — whole-query case-insensitive substring on
# .body only — into a sandbox copy of wisdom-search.sh, then proves the
# regression's core assertions fail against it (title-term and tag-term
# queries return 0 under the old matcher while the fixed matcher returns >=1).
set -o errexit

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TESTS_PASSED=0; TESTS_FAILED=0

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

# 1. Build a reverted copy: swap the tokenized JQ_FILTER for the legacy
#    body-only whole-query substring filter.
cp "$REPO_ROOT/scripts/wisdom/wisdom-search.sh" "$SANDBOX/wisdom-search-old.sh"
cp "$REPO_ROOT/scripts/wisdom/wisdom-common.sh" "$SANDBOX/wisdom-common.sh"
python3 - "$SANDBOX/wisdom-search-old.sh" <<'PYEOF'
import sys
path = sys.argv[1]
with open(path) as f:
    src = f.read()
new_filter = """    JQ_FILTER '
        . as $e
        | (($e.title // "") + " " + ($e.body // "") + " " + (($e.tags // []) | (if type == "array" then join(" ") else tostring end))) as $hay
        | ($q | ascii_downcase | [splits("\\\\s+") | select(length > 0)]) as $terms
        | select(
            (($e.body // "") | ascii_downcase | contains($q | ascii_downcase))
            or ([$terms[] | . as $t | select($hay | ascii_downcase | contains($t))] | length) > 0
          )'"""
legacy = """    JQ_FILTER="select(.body | ascii_downcase | contains(\\$q | ascii_downcase))\""""
start = src.index("    JQ_FILTER='")
end = src.index("          )'", start) + len("          )'")
patched = src[:start] + legacy + src[end:]
with open(path, "w") as f:
    f.write(patched)
PYEOF
# sanity: reverted copy no longer contains the tokenized filter
if grep -qF 'or ([$terms[]' "$SANDBOX/wisdom-search-old.sh"; then
    echo "FAILURE: kill-test 030 broken — reverted copy still contains tokenized filter"
    exit 1
fi

# 2. Sandbox store identical to regression 030's.
export WISDOM_ROOT="$SANDBOX"
cat > "$SANDBOX/system.jsonl" <<'EOF'
{"id":"t-title-hit","type":"gotcha","status":"active","authority":"verified","scope":"system","title":"typography","body":"loading the skill requires its SKILL.md frontmatter","tags":["web"],"quality_score":7}
{"id":"t-tag-hit","type":"pattern","status":"active","authority":"verified","scope":"system","title":"browser config","body":"set the default handler via xdg settings","tags":["browser"],"quality_score":6}
{"id":"t-body-hit","type":"fact","status":"active","authority":"verified","scope":"system","title":"unrelated","body":"retry plugin handles provider quota exhaustion","tags":["opencode"],"quality_score":5}
EOF

hit_count() {
    local n=0
    n=$(bash "$SANDBOX/wisdom-search-old.sh" "$1" --no-touch --json 2>/dev/null | jq 'length' 2>/dev/null) || n=0
    printf '%s' "$n"
}

# 3. Old matcher must return 0 for the title-term and tag-term queries —
#    exactly what regression 030's assertions flag as FAIL.
for q in "typography skill" "browser default"; do
    n=$(hit_count "$q")
    if [[ "$n" -eq 0 ]]; then
        TESTS_PASSED=$((TESTS_PASSED+1))  # old shape fails regression 030's assertion → detection proven
    else
        echo "FAILURE: kill-test 030 broken — reverted matcher returned $n results for '$q' (want 0)"
        TESTS_FAILED=$((TESTS_FAILED+1))
    fi
done

# 4. Whole-query body substring still works under the old matcher (guards
#    against the kill-test over-reverting).
n=$(hit_count "provider quota exhaustion")
if [[ "$n" -ge 1 ]]; then TESTS_PASSED=$((TESTS_PASSED+1)); else
    echo "FAILURE: kill-test 030 broken — reverted matcher lost body substring matching"
    TESTS_FAILED=$((TESTS_FAILED+1))
fi

if [[ $TESTS_FAILED -gt 0 ]]; then exit 1; fi
echo "PROVED: kill-test 030 — regression 030 detects the reverted body-only matcher"
