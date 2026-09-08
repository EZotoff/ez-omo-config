#!/usr/bin/env bash
# Kill-test 018: proves regression 018 detects a plugin with stray function exports.
#
# Builds a temp copy of the plugin entry with a reintroduced stray function
# export (the exact 2026-09-08 bug shape: a detection helper exported "for
# tests"), runs the same export-surface check scoped to the temp dir, and
# expects it to FAIL — proving the regression catches reintroduction.
set -o errexit
source "$(cd "$(dirname "$0")/.." && pwd)/helpers.sh"

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
command -v bun >/dev/null 2>&1 || { echo "FAIL: bun not found (hard dependency of this config)"; exit 1; }

KILL_TMP="$(mktemp -d)"
trap 'rm -rf "$KILL_TMP"' EXIT

# Reproduce the pre-fix layout: plugin entry + helpers submodule beside it.
cp "$REPO_ROOT/plugins/review-enforcer.ts" "$KILL_TMP/review-enforcer.ts"
mkdir -p "$KILL_TMP/review-enforcer"
cp "$REPO_ROOT/plugins/review-enforcer/helpers.ts" "$KILL_TMP/review-enforcer/helpers.ts"

# Reintroduce the bug: a stray exported detection helper.
cat >> "$KILL_TMP/review-enforcer.ts" <<'EOF'

export function detectRecursionKiller(output: string, argsStr: string): string | null {
	return output.includes("[REVIEW-TASK]") || argsStr.includes("[REVIEW-TASK]") ? "[REVIEW-TASK]" : null
}
EOF

# The surface check (same logic as 018) must flag the temp module.
if PLUGINS_DIR="$KILL_TMP" CONFIG_DIR="$KILL_TMP/no-config" bun -e '
const { readdirSync } = await import("node:fs")
const { join } = await import("node:path")
const { pathToFileURL } = await import("node:url")
const mods = []
for (const f of readdirSync(process.env.PLUGINS_DIR)) if (f.endsWith(".ts")) mods.push(join(process.env.PLUGINS_DIR, f))
let bad = 0
for (const p of mods) {
  const mod = await import(pathToFileURL(p).href)
  const keys = Object.keys(mod)
  const nonFn = keys.filter((k) => typeof mod[k] !== "function")
  const distinct = keys.filter((k) => k !== "default" && mod[k] !== mod.default)
  if (nonFn.length > 0 || distinct.length > 0) {
    bad++
    console.error(`BAD SURFACE ${p}: non-function=[${nonFn.join(",")}] distinct-from-default=[${distinct.join(",")}]`)
  }
}
if (bad > 0) process.exit(1)
console.log(`export-surface OK across ${mods.length} plugin modules`)
'; then
    echo "FAILURE: kill-test 018 broken — surface check passed despite stray export"
    TESTS_FAILED=$((TESTS_FAILED + 1))
else
    TESTS_PASSED=$((TESTS_PASSED + 1))
fi

if [[ $TESTS_FAILED -gt 0 ]]; then
    exit 1
fi
echo "PROVED: regression 018 detects reintroduced stray plugin exports"
