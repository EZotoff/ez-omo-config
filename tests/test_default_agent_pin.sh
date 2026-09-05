#!/usr/bin/env bash

# Regression guard: Sisyphus must be the pinned default agent.
#
# Context (2026-09-05 incident): sessions created through the OC Beacon
# Android client (opencode-interactive.service, port 3030) defaulted to the
# hidden "build" agent. The client reads default_agent from the served
# /config; during server bootstrap that field is only present after the OMO
# config hook runs, leaving a window where a config-reading client sees no
# default and falls back to its own hardcoded "build". Pinning the key in
# opencode.json makes it available from the first request, independent of
# plugin hook timing. OMO preserves a configured default_agent
# (agent-config-assembly.ts applyDefaultAgent).

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TESTS_PASSED=0
TESTS_FAILED=0

pass() {
    echo "PASS: $1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

fail() {
    echo "FAIL: $1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

OPENCODE_JSON="$REPO_ROOT/configs/opencode/opencode.json"
OMO_JSON="$REPO_ROOT/configs/oh-my-openagent/oh-my-openagent.json"

# 1. opencode.json pins default_agent to Sisyphus
if python3 -c "
import json, sys
c = json.load(open('$OPENCODE_JSON'))
sys.exit(0 if c.get('default_agent') == 'Sisyphus' else 1)
"; then
    pass "opencode.json default_agent == Sisyphus"
else
    fail "opencode.json default_agent is not 'Sisyphus' (got: $(python3 -c "import json; print(json.load(open('$OPENCODE_JSON')).get('default_agent'))"))"
fi

# 2. The pinned agent must exist in the OMO agent registry
if python3 -c "
import json, sys
c = json.load(open('$OMO_JSON'))
sys.exit(0 if 'sisyphus' in (c.get('agents') or {}) else 1)
"; then
    pass "oh-my-openagent.json defines agent 'sisyphus'"
else
    fail "oh-my-openagent.json no longer defines agent 'sisyphus' — default_agent pin would dangle"
fi

# 3. Sisyphus must not be disabled via sisyphus_agent.disabled
if python3 -c "
import json, sys
c = json.load(open('$OMO_JSON'))
sys.exit(1 if c.get('sisyphus_agent', {}).get('disabled') is True else 0)
"; then
    pass "sisyphus agent not disabled in OMO config"
else
    fail "sisyphus_agent.disabled == true would bypass Sisyphus default-agent assembly"
fi

echo ""
echo "default-agent pin: $TESTS_PASSED passed, $TESTS_FAILED failed"
if [[ $TESTS_FAILED -gt 0 ]]; then
    exit 1
fi
