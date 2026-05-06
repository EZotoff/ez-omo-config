#!/usr/bin/env bash
set -euo pipefail

source tests/helpers.sh

BLOCK_FILE="_test_plan_completion_block.txt"

cleanup() {
    rm -f "$BLOCK_FILE"
}
trap cleanup EXIT

# Extract PLAN_COMPLETION_INSTRUCTION block using Python
# This avoids grepping the whole TypeScript file and ensures deterministic parsing
if ! python3 << 'PYEOF'
import re, sys

with open('plugins/review-enforcer.ts') as f:
    content = f.read()

# Verify exactly one declaration exists
count = len(re.findall(r'const PLAN_COMPLETION_INSTRUCTION = ', content))
if count != 1:
    print(f'FAIL: Expected exactly 1 PLAN_COMPLETION_INSTRUCTION declaration, found {count}')
    sys.exit(1)

start = content.find('const PLAN_COMPLETION_INSTRUCTION =')
if start == -1:
    print('FAIL: Could not find PLAN_COMPLETION_INSTRUCTION start position')
    sys.exit(1)

# Extract the template literal content (handle escaped backticks correctly)
pattern = r'const PLAN_COMPLETION_INSTRUCTION = `((?:[^`\\]|\\.)*)`'
match = re.search(pattern, content, re.DOTALL)
if not match:
    print('FAIL: Could not extract PLAN_COMPLETION_INSTRUCTION template literal')
    sys.exit(1)

end = start + len(match.group(0))

with open('_test_plan_completion_block.txt', 'w') as out:
    out.write(match.group(1))
print('PASS: Block extracted successfully')
PYEOF
then
    echo "FAIL: Extraction of PLAN_COMPLETION_INSTRUCTION block failed"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    exit 1
fi

TESTS_PASSED=$((TESTS_PASSED + 1))

assert_grep "SYNCHRONOUS full-branch review" "$BLOCK_FILE"
assert_grep "Evidence-state consolidation required" "$BLOCK_FILE"
assert_grep "Closeout Summary" "$BLOCK_FILE"
assert_grep "TLDR of functionality created" "$BLOCK_FILE"
assert_grep "Expected behavior" "$BLOCK_FILE"
assert_grep "User testing follow-up" "$BLOCK_FILE"
assert_grep "Not verified live: \[missing state\]" "$BLOCK_FILE"

assert_grep "response-only" "$BLOCK_FILE"
assert_grep '\.sisyphus/' "$BLOCK_FILE"
assert_grep "notepads" "$BLOCK_FILE"
assert_grep "evidence files" "$BLOCK_FILE"
assert_grep "wisdom" "$BLOCK_FILE"

if [[ "$TESTS_FAILED" -gt 0 ]]; then
    echo "FAIL: $TESTS_FAILED test(s) failed, $TESTS_PASSED passed"
    exit 1
fi

echo "PASS: All $TESTS_PASSED test(s) passed"
exit 0
