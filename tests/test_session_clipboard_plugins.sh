#!/usr/bin/env bash
# Regression test: /session-info, /session-id, /vscode plugin registration and non-throw abort pattern.
#
# Background: OpenCode 1.17.5+ (upstream issue #32253) surfaces plugin hook errors
# as TUI error toasts via the session.error SSE event. The three clipboard/launcher
# plugins previously used `throw new Error("__xxx_handled__")` to abort the command
# pipeline. This throw now causes TUI error spam. The fix is:
#   1. Register the plugins in opencode.json#plugin (they were never registered).
#   2. Replace the throw with output.parts in-place mutation.
#   3. Exclude the commands from OMO's auto-slash-command hook.
#
# This test verifies all three aspects.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS=0
FAIL=0

ok()   { PASS=$((PASS + 1)); echo "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "FAIL: $1"; }

# ---------------------------------------------------------------------------
# 1. Plugins registered in opencode.json#plugin
# ---------------------------------------------------------------------------

for plugin in session-info.ts session-id.ts vscode.ts; do
	entry="file:///home/ezotoff/.opencode/plugin/${plugin}"
	if python3 -c "
import json, sys
d = json.load(open('${REPO_ROOT}/configs/opencode/opencode.json'))
plugins = d.get('plugin', [])
sys.exit(0 if '${entry}' in plugins else 1)
" 2>/dev/null; then
		ok "opencode.json#plugin contains ${plugin}"
	else
		fail "opencode.json#plugin missing ${plugin} (expected '${entry}')"
	fi
done

# ---------------------------------------------------------------------------
# 2. Plugins do NOT use throw-based abort (the regression pattern)
# ---------------------------------------------------------------------------

for plugin in plugins/session-info.ts plugins/session-id.ts plugins/vscode.ts; do
	filepath="${REPO_ROOT}/${plugin}"
	if grep -q 'throw new Error("__' "${filepath}" 2>/dev/null; then
		fail "${plugin} still uses throw-based abort (grep found '__*_handled__' throw)"
	else
		ok "${plugin} does not use throw-based abort"
	fi
done

# ---------------------------------------------------------------------------
# 3. Plugins use output.parts in-place mutation for non-throw suppression
# ---------------------------------------------------------------------------

for plugin in plugins/session-info.ts plugins/session-id.ts plugins/vscode.ts; do
	filepath="${REPO_ROOT}/${plugin}"
	if grep -q 'output\.parts\.length = 0' "${filepath}" 2>/dev/null; then
		ok "${plugin} uses output.parts.length = 0 (in-place clear)"
	else
		fail "${plugin} missing output.parts.length = 0"
	fi
done

# ---------------------------------------------------------------------------
# 4. OMO EXCLUDED_COMMANDS includes session-info, session-id, vscode
# ---------------------------------------------------------------------------

OMO_DIST="${OMO_DIST:-/home/ezotoff/oh-my-openagent-v4.12.1/dist/index.js}"
if [ -f "${OMO_DIST}" ]; then
	for cmd in session-info session-id vscode; do
		if grep -q "\"${cmd}\"" "${OMO_DIST}" 2>/dev/null; then
			ok "OMO EXCLUDED_COMMANDS contains '${cmd}'"
		else
			fail "OMO EXCLUDED_COMMANDS missing '${cmd}' in ${OMO_DIST}"
		fi
	done
else
	echo "SKIP: OMO dist not found at ${OMO_DIST} (set OMO_DIST env to test)"
fi

# ---------------------------------------------------------------------------
# 5. Patch documentation reflects the extended exclusion list
# ---------------------------------------------------------------------------

PATCH_DOC="${REPO_ROOT}/.sisyphus/patches/omo--exclude-selected-auto-slash-commands.md"
if [ -f "${PATCH_DOC}" ]; then
	for cmd in session-info session-id vscode; do
		if grep -q "${cmd}" "${PATCH_DOC}" 2>/dev/null; then
			ok "Patch doc mentions '${cmd}'"
		else
			fail "Patch doc missing '${cmd}'"
		fi
	done
else
	fail "Patch doc not found: ${PATCH_DOC}"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
echo "Tests passed: ${PASS}"
echo "Tests failed: ${FAIL}"

if [ "${FAIL}" -gt 0 ]; then
	exit 1
fi
