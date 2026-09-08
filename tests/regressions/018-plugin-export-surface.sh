#!/usr/bin/env bash
# Regression 018: plugin modules may not export anything except the plugin function.
#
# Bug (2026-09-08, blocked the ez-omo-bench flash-600k campaign): review-enforcer.ts
# exported seven pure helper functions for its test harness. OpenCode's plugin loader
# (packages/opencode/src/plugin/index.ts getLegacyPlugins — semantics unchanged since
# at least v1.17.9) treats EVERY function export of a plugin module as a plugin
# constructor and calls it with (PluginInput, options). On every fresh server the
# loader ran detectRecursion(PluginInput, ...) → "output.includes is not a function"
# → "failed to load plugin review-enforcer". Enforcement survived only because
# alphabetical export order ran the real plugin first, and the damaged load
# intermittently lost the startup race, killing sessions with
# `default agent "Sisyphus" not found` (reproduced 3/3 with a 1.28MB prompt).
#
# Fix: helpers moved to plugins/review-enforcer/helpers.ts (the loader never
# auto-loads subdirectories); plugin entry files export only plugin + default.
#
# This regression checks EVERY repo plugin module's export surface, not just
# review-enforcer's — the loader contract applies to all of them.
set -o errexit
source "$(cd "$(dirname "$0")/.." && pwd)/helpers.sh"

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
command -v bun >/dev/null 2>&1 || { echo "FAIL: bun not found (hard dependency of this config)"; exit 1; }

# The moved-out helpers module must exist and the plugin must import it...
assert_file_exists "$REPO_ROOT/plugins/review-enforcer/helpers.ts"
assert_grep 'from "\./review-enforcer/helpers"' "$REPO_ROOT/plugins/review-enforcer.ts"
# ...and the plugin entry must no longer export helpers directly.
assert_no_grep '^export function' "$REPO_ROOT/plugins/review-enforcer.ts"

# Loader-contract check across every plugin module (auto-discovered top-level
# plugins/*.ts + config-array configs/opencode/*.mjs): each module's export
# surface must contain only functions, and every named function export must be
# the SAME value as `default` (the loader calls each distinct export as a
# plugin constructor with PluginInput — stray helpers crash or misbehave).
if REPO_ROOT="$REPO_ROOT" PLUGINS_DIR="$REPO_ROOT/plugins" CONFIG_DIR="$REPO_ROOT/configs/opencode" bun -e '
const { readdirSync, existsSync } = await import("node:fs")
const { join } = await import("node:path")
const { pathToFileURL } = await import("node:url")
const pluginsDir = process.env.PLUGINS_DIR
const configDir = process.env.CONFIG_DIR
const mods = []
for (const f of readdirSync(pluginsDir)) if (f.endsWith(".ts")) mods.push(join(pluginsDir, f))
if (existsSync(configDir)) {
  for (const f of readdirSync(configDir)) if (f.endsWith(".mjs")) mods.push(join(configDir, f))
}
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
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "FAIL: plugin export-surface check failed (see output above)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

if [[ $TESTS_FAILED -gt 0 ]]; then
    echo "FAILURE: plugin export-surface contract violated (see tests/regressions/018-plugin-export-surface.sh)"
    exit 1
fi
echo "PASS: all plugin modules export only the plugin function"
