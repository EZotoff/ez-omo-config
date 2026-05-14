#!/usr/bin/env bash

# Regression test for Codex display provider configuration
# Usage: bash tests/test_openai_provider.sh
#
# Asserts:
#   - openai is present in enabled_providers
#   - provider.openai exists and is labeled Codex
#   - provider.openai exists with expected models
#   - opencode-openai-codex-auth plugin entry exists

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/helpers.sh"

CONFIG_FILE="$REPO_ROOT/configs/opencode/opencode.json"

assert_file_exists "$CONFIG_FILE"

python3 -c "
import json, sys

with open('$CONFIG_FILE') as f:
    data = json.load(f)

enabled = data.get('enabled_providers', [])
if 'openai' not in enabled:
    print('FAIL: openai not in enabled_providers')
    sys.exit(1)
print('PASS: openai in enabled_providers')

provider = data.get('provider', {})
if 'openai' not in provider:
    print('FAIL: provider.openai missing')
    sys.exit(1)
if provider.get('openai', {}).get('name') != 'Codex':
    print('FAIL: provider.openai has unexpected display name: %r' % provider.get('openai', {}).get('name'))
    sys.exit(1)
print('PASS: provider.openai exists and is labeled Codex')

openai_models = provider.get('openai', {}).get('models', {})
expected_models = ['gpt-5.2', 'gpt-5.4-2026-03-05', 'gpt-5.3-codex', 'gpt-5.1-codex-max']
missing = [m for m in expected_models if m not in openai_models]
if missing:
    print(f'FAIL: missing expected models: {missing}')
    sys.exit(1)
print(f'PASS: all expected models present ({len(expected_models)})')

plugins = data.get('plugin', [])
if not any('opencode-openai-codex-auth' in str(p) for p in plugins):
    print('FAIL: opencode-openai-codex-auth plugin entry missing')
    sys.exit(1)
print('PASS: opencode-openai-codex-auth plugin entry exists')
" || {
    echo "Codex provider regression test failed"
    exit 1
}

TESTS_PASSED=4
TESTS_FAILED=0

echo ""
echo "Tests passed: $TESTS_PASSED"
echo "Tests failed: $TESTS_FAILED"
echo ""

exit 0
