#!/usr/bin/env bash

# Regression test for Codex display provider configuration
# Usage: bash tests/test_openai_provider.sh
#
# Asserts:
#   - openai is present in enabled_providers
#   - provider.openai exists and is labeled Codex
#   - provider.openai exists with expected models
#   - opencode-openai-codex-auth plugin entry exists
#   - OMO GPT-heavy agents/categories prefer openai models with GitHub Copilot fallbacks
#   - quick/unspecified-low prefer Spark over DeepSeek and Gemini regressions point back to GitHub Copilot Gemini 3.1 Pro Preview

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/helpers.sh"

CONFIG_FILE="$REPO_ROOT/configs/opencode/opencode.json"
OMO_CONFIG_FILE="$REPO_ROOT/configs/oh-my-openagent/oh-my-openagent.json"

assert_file_exists "$CONFIG_FILE"
assert_file_exists "$OMO_CONFIG_FILE"

python3 -c "
import json, sys

with open('$CONFIG_FILE') as f:
    data = json.load(f)
with open('$OMO_CONFIG_FILE') as f:
    omo = json.load(f)

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
expected_models = ['gpt-5.2', 'gpt-5.5', 'gpt-5.4', 'gpt-5.4-2026-03-05', 'gpt-5.3-codex', 'gpt-5.3-codex-spark', 'gpt-5.1-codex-max']
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

expected_agent_models = {
    'sisyphus': 'openai/gpt-5.5',
    'hephaestus': 'openai/gpt-5.3-codex',
    'oracle': 'openai/gpt-5.5',
    'prometheus': 'openai/gpt-5.5',
    'metis': 'openai/gpt-5.5',
    'momus': 'openai/gpt-5.5',
}
expected_category_models = {
    'ultrabrain': 'openai/gpt-5.5',
    'deep': 'openai/gpt-5.3-codex',
    'quick': 'openai/gpt-5.3-codex-spark',
    'unspecified-low': 'openai/gpt-5.3-codex-spark',
    'unspecified-high': 'openai/gpt-5.4',
    'mephistopheles': 'openai/gpt-5.5',
}

expected_gemini_routes = {
    ('agents', 'multimodal-looker'): 'github-copilot/gemini-3.1-pro-preview',
    ('agents', 'frontend-ui-ux-engineer'): 'github-copilot/gemini-3.1-pro-preview',
    ('categories', 'visual-engineering'): 'github-copilot/gemini-3.1-pro-preview',
    ('categories', 'artistry'): 'github-copilot/gemini-3.1-pro-preview',
}

agents = omo.get('agents', {})
categories = omo.get('categories', {})
for name, expected in expected_agent_models.items():
    actual = agents.get(name, {}).get('model')
    if actual != expected:
        print(f'FAIL: agents.{name}.model expected {expected!r}, got {actual!r}')
        sys.exit(1)
    fallbacks = agents.get(name, {}).get('fallback_models', [])
    if name == 'sisyphus':
        if fallbacks != ['kimi-for-coding-oauth/kimi-for-coding']:
            print(f'FAIL: agents.sisyphus.fallback_models has unexpected value: {fallbacks!r}')
            sys.exit(1)
        continue
    if not any(str(model).startswith('github-copilot/gpt-') for model in fallbacks):
        print(f'FAIL: agents.{name}.fallback_models lacks GitHub Copilot GPT fallback')
        sys.exit(1)
for name, expected in expected_category_models.items():
    actual = categories.get(name, {}).get('model')
    if actual != expected:
        print(f'FAIL: categories.{name}.model expected {expected!r}, got {actual!r}')
        sys.exit(1)
    fallbacks = categories.get(name, {}).get('fallback_models', [])
    if not any(str(model).startswith('github-copilot/gpt-') for model in fallbacks):
        print(f'FAIL: categories.{name}.fallback_models lacks GitHub Copilot GPT fallback')
        sys.exit(1)
print('PASS: OMO GPT-heavy routes prefer openai with GitHub Copilot fallbacks')

for name in ('quick', 'unspecified-low'):
    route = categories.get(name, {})
    if route.get('variant') != 'medium':
        print(f'FAIL: categories.{name}.variant expected \'medium\', got {route.get("variant")!r}')
        sys.exit(1)
    fallbacks = route.get('fallback_models', [])
    if 'github-copilot/gpt-5.3-codex' not in fallbacks:
        print(f'FAIL: categories.{name}.fallback_models missing github-copilot/gpt-5.3-codex')
        sys.exit(1)
print('PASS: quick and unspecified-low prefer Spark with Codex fallback')

for (scope, name), expected in expected_gemini_routes.items():
    actual = (agents if scope == 'agents' else categories).get(name, {}).get('model')
    if actual != expected:
        print(f'FAIL: {scope}.{name}.model expected {expected!r}, got {actual!r}')
        sys.exit(1)

for name in ('oracle', 'momus'):
    fallbacks = agents.get(name, {}).get('fallback_models', [])
    if 'github-copilot/gemini-3.1-pro-preview' not in fallbacks:
        print(f'FAIL: agents.{name}.fallback_models missing github-copilot/gemini-3.1-pro-preview')
        sys.exit(1)
print('PASS: Gemini 3.1 Pro Preview routes restored to GitHub Copilot')

unspecified_high = categories.get('unspecified-high', {})
if unspecified_high.get('fallback_models') != ['github-copilot/gpt-5.4', 'kimi-for-coding-oauth/kimi-for-coding']:
    print(f'FAIL: categories.unspecified-high.fallback_models has unexpected order: {unspecified_high.get("fallback_models")!r}')
    sys.exit(1)

meph = categories.get('mephistopheles', {})
if meph.get('variant') != 'high':
    print(f'FAIL: categories.mephistopheles.variant expected \'high\', got {meph.get("variant")!r}')
    sys.exit(1)
if 'github-copilot/gpt-5.5' not in meph.get('fallback_models', []):
    print('FAIL: categories.mephistopheles.fallback_models missing github-copilot/gpt-5.5')
    sys.exit(1)
print('PASS: unspecified-high, ultrabrain, and mephistopheles use requested GPT routing')

dream_model = omo.get('aspectDynamics', {}).get('dreamAgent', {}).get('model', {})
if dream_model != {'providerID': 'openai', 'modelID': 'gpt-5.4'}:
    print(f'FAIL: aspectDynamics.dreamAgent.model has unexpected value: {dream_model!r}')
    sys.exit(1)
print('PASS: aspectDynamics dream agent GPT route prefers openai')
" || {
    echo "Codex provider regression test failed"
    exit 1
}

TESTS_PASSED=8
TESTS_FAILED=0

echo ""
echo "Tests passed: $TESTS_PASSED"
echo "Tests failed: $TESTS_FAILED"
echo ""

exit 0
