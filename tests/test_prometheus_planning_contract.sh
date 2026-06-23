#!/usr/bin/env bash
set -euo pipefail

source tests/helpers.sh

TMP_FILE="_test_prometheus_prompt_append.txt"

cleanup() {
    rm -f "$TMP_FILE"
}
trap cleanup EXIT

# Extract prompt_append from config and verify required contract literals
# Uses Python 'in' operator (literal substring check) — NOT regex —
# because fragments like .sisyphus/plans/*.md contain regex metacharacters
if ! python3 << 'PYEOF'
import json, sys

with open('configs/oh-my-openagent/oh-my-openagent.json') as f:
    data = json.load(f)

pa = data.get('agents', {}).get('prometheus', {}).get('prompt_append', None)

if pa is None or not isinstance(pa, str):
    print('FAIL: agents.prometheus.prompt_append is missing or not a string')
    sys.exit(1)

# Write prompt_append to temp file for debugging
with open('_test_prometheus_prompt_append.txt', 'w') as out:
    out.write(pa)

# Required contract literals for the config-layer prompt_append.
# The HTML Proposal+Design Packet contract lives in the OMO prometheus agent
# source (~/oh-my-openagent/src/agents/prometheus/), not in this config field.
required_literals = [
    'wisdom',
    'wisdom-search.sh',
    'Vera tool-selection decision tree',
    'vera search',
    'vera grep',
    'repo_implemented',
    'live_file_installed',
    'active_config_registered',
    'runtime_loaded',
    'real_project_behavior_proven',
]

all_pass = True
for lit in required_literals:
    if lit not in pa:
        print(f'FAIL: Required literal not found in prompt_append: {lit}')
        all_pass = False

if all_pass:
    print('PASS: All required literals found in prompt_append')
    sys.exit(0)
else:
    sys.exit(1)
PYEOF
then
    echo "FAIL: Prometheus planning contract check failed"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    exit 1
fi

TESTS_PASSED=$((TESTS_PASSED + 1))

if [[ "$TESTS_FAILED" -gt 0 ]]; then
    echo "FAIL: $TESTS_FAILED test(s) failed, $TESTS_PASSED passed"
    exit 1
fi

echo "PASS: All $TESTS_PASSED test(s) passed"
exit 0
