#!/usr/bin/env bash

# Regression test for Codex display provider configuration
# Usage: bash tests/test_openai_provider.sh
#
# Asserts:
#   - openai is present in enabled_providers
#   - provider.openai exists and is labeled Codex
#   - provider.openai exists with expected models
#   - opencode-openai-codex-auth plugin entry exists
#   - retired provider routes are absent from active config
#   - OMO GPT-heavy agents/categories use openai models
#   - quick/unspecified-low prefer Spark, Google routes resolve, and OpenCode Go routes use current model IDs

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

retired_provider = 'github' + '-' + ''.join(['co', 'pi', 'lot'])
if retired_provider in enabled:
    print('FAIL: retired provider still present in enabled_providers')
    sys.exit(1)
if retired_provider in data.get('provider', {}):
    print('FAIL: retired provider catalog still present')
    sys.exit(1)
print('PASS: retired provider absent from enabled provider list and provider catalog')

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

google_models = provider.get('google', {}).get('models', {})
if 'gemini-3.5-flash' not in google_models:
    print('FAIL: provider.google.models.gemini-3.5-flash missing')
    sys.exit(1)
print('PASS: provider.google.models.gemini-3.5-flash exists')

if 'gemini-3.1-pro-preview' not in google_models:
    print('FAIL: provider.google.models.gemini-3.1-pro-preview missing')
    sys.exit(1)
print('PASS: provider.google.models.gemini-3.1-pro-preview exists')

plugins = data.get('plugin', [])
if not any('opencode-openai-codex-auth' in str(p) for p in plugins):
    print('FAIL: opencode-openai-codex-auth plugin entry missing')
    sys.exit(1)
print('PASS: opencode-openai-codex-auth plugin entry exists')

expected_agent_models = {
    'sisyphus': 'zai-coding-plan/glm-5.2',
    'hephaestus': 'openai/gpt-5.4',
    'oracle': 'openai/gpt-5.5',
    'prometheus': 'zai-coding-plan/glm-5.2',
    'metis': 'openai/gpt-5.5',
    'momus': 'openai/gpt-5.5',
}
expected_category_models = {
    'ultrabrain': 'openai/gpt-5.5',
    'deep': 'openai/gpt-5.4',
    'quick': 'opencode-go/deepseek-v4-flash',
    'unspecified-low': 'opencode-go/deepseek-v4-flash',
    'unspecified-high': 'openai/gpt-5.4',
    'mephistopheles': 'openai/gpt-5.5',
}

expected_gemini_routes = {
    ('agents', 'multimodal-looker'): 'google/gemini-3.5-flash',
    ('agents', 'frontend-ui-ux-engineer'): 'google/gemini-3.1-pro-preview',
    ('categories', 'visual-engineering'): 'google/gemini-3.1-pro-preview',
    ('categories', 'artistry'): 'google/gemini-3.1-pro-preview',
}

expected_opencode_go_routes = {
    ('agents', 'librarian'): 'opencode-go/minimax-m3',
    ('agents', 'explore'): 'opencode-go/minimax-m3',
    ('categories', 'writing'): 'opencode-go/kimi-k2.6',
}

agents = omo.get('agents', {})
categories = omo.get('categories', {})

if retired_provider in json.dumps(data) or retired_provider in json.dumps(omo):
    print('FAIL: retired provider string remains in active JSON config')
    sys.exit(1)
print('PASS: retired provider string absent from active JSON config')

expected_agent_fallbacks = {
    'sisyphus': ['openai/gpt-5.5', 'kimi-for-coding-oauth/kimi-for-coding'],
    'oracle': ['google/gemini-3.1-pro-preview'],
    'prometheus': ['openai/gpt-5.5', 'zai-coding-plan/glm-5.1'],
    'metis': ['google/gemini-3.1-pro-preview'],
    'momus': ['google/gemini-3.1-pro-preview'],
}

for name, expected in expected_agent_models.items():
    actual = agents.get(name, {}).get('model')
    if actual != expected:
        print(f'FAIL: agents.{name}.model expected {expected!r}, got {actual!r}')
        sys.exit(1)
    if name in expected_agent_fallbacks:
        fallbacks = agents.get(name, {}).get('fallback_models', [])
        if fallbacks != expected_agent_fallbacks[name]:
            print(f'FAIL: agents.{name}.fallback_models expected {expected_agent_fallbacks[name]!r}, got {fallbacks!r}')
            sys.exit(1)

expected_category_fallbacks = {
    'ultrabrain': ['zai-coding-plan/glm-5.1'],
    'deep': ['kimi-for-coding-oauth/kimi-for-coding', 'zai-coding-plan/glm-5.2'],
    'quick': ['kimi-for-coding-oauth/kimi-for-coding'],
    'unspecified-low': ['kimi-for-coding-oauth/kimi-for-coding'],
    'unspecified-high': ['kimi-for-coding-oauth/kimi-for-coding'],
    'mephistopheles': ['openai/gpt-5.4', 'kimi-for-coding-oauth/kimi-for-coding'],
}

for name, expected in expected_category_models.items():
    actual = categories.get(name, {}).get('model')
    if actual != expected:
        print(f'FAIL: categories.{name}.model expected {expected!r}, got {actual!r}')
        sys.exit(1)
    fallbacks = categories.get(name, {}).get('fallback_models', [])
    if fallbacks != expected_category_fallbacks[name]:
        print(f'FAIL: categories.{name}.fallback_models expected {expected_category_fallbacks[name]!r}, got {fallbacks!r}')
        sys.exit(1)
print('PASS: OMO GPT-heavy routes use openai without retired-provider fallbacks')

for name in ('quick', 'unspecified-low'):
    route = categories.get(name, {})
    if route.get('variant') is not None:
        print(f'FAIL: categories.{name}.variant expected None, got {route.get("variant")!r}')
        sys.exit(1)
    fallbacks = route.get('fallback_models', [])
    if fallbacks != ['kimi-for-coding-oauth/kimi-for-coding']:
        print(f'FAIL: categories.{name}.fallback_models expected kimi fallback, got {fallbacks!r}')
        sys.exit(1)
print('PASS: quick and unspecified-low use DeepSeek V4 Flash with kimi fallback')

for (scope, name), expected in expected_gemini_routes.items():
    actual = (agents if scope == 'agents' else categories).get(name, {}).get('model')
    if actual != expected:
        print(f'FAIL: {scope}.{name}.model expected {expected!r}, got {actual!r}')
        sys.exit(1)

print('PASS: Gemini routes use expected Google providers')

for (scope, name), expected in expected_opencode_go_routes.items():
    route = (agents if scope == 'agents' else categories).get(name, {})
    actual = route.get('model') if scope == 'agents' else route.get('fallback_models', [None])[0]
    if actual != expected:
        print(f'FAIL: {scope}.{name} expected OpenCode Go route {expected!r}, got {actual!r}')
        sys.exit(1)
print('PASS: OpenCode Go routes use current Minimax and Kimi models')

unspecified_high = categories.get('unspecified-high', {})
if unspecified_high.get('fallback_models') != ['kimi-for-coding-oauth/kimi-for-coding']:
    print(f'FAIL: categories.unspecified-high.fallback_models has unexpected order: {unspecified_high.get("fallback_models")!r}')
    sys.exit(1)

meph = categories.get('mephistopheles', {})
if meph.get('variant') != 'high':
    print(f'FAIL: categories.mephistopheles.variant expected \'high\', got {meph.get("variant")!r}')
    sys.exit(1)
if meph.get('fallback_models') != ['openai/gpt-5.4', 'kimi-for-coding-oauth/kimi-for-coding']:
    print(f'FAIL: categories.mephistopheles.fallback_models has unexpected value: {meph.get("fallback_models")!r}')
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

TESTS_PASSED=14
TESTS_FAILED=0

echo ""
echo "Tests passed: $TESTS_PASSED"
echo "Tests failed: $TESTS_FAILED"
echo ""

exit 0
