#!/usr/bin/env bash
# Regression test: ensure verbose agent display names are NOT emitted as
# runtime values in AGENT_DISPLAY_NAMES.
#
# Background: omo--clean-agent-display-names originally claimed to strip
# verbose suffixes ("Sisyphus - Ultraworker", "Momus - Plan Critic", etc.)
# but only the dist bundle was hand-patched. The source AGENT_DISPLAY_NAMES
# still hardcoded the verbose forms, so every rebuild silently regressed.
# This test catches that exact regression.
#
# Important: verbose strings MAY legitimately appear in the bundle as
#   - lowercase keys in LEGACY_DISPLAY_NAMES (for resolving old sessions)
#   - exact-case keys in AGENT_NAME_MAP migration table (same purpose)
# The test specifically checks the VALUE side of AGENT_DISPLAY_NAMES
# assignments to ensure verbose forms are not emitted at runtime.
set -euo pipefail

FORK="${OMO_FORK:-/home/ezotoff/oh-my-openagent-v4.12.1}"
DIST_MAIN="$FORK/dist/index.js"
DIST_CLI="$FORK/dist/cli/index.js"

if [[ ! -f "$DIST_MAIN" ]]; then
  echo "SKIP: $DIST_MAIN not present (OMO fork not built yet)"
  exit 0
fi

fail=0

# Minified bundles may insert variable whitespace around colons. Tolerate that
# by allowing zero-or-more whitespace on either side of the colon when checking.
# Expected plain assignments (key:"Value") in AGENT_DISPLAY_NAMES.
EXPECTED_PLAIN=(
  'sisyphus:"Sisyphus"'
  'hephaestus:"Hephaestus"'
  'prometheus:"Prometheus"'
  'atlas:"Atlas"'
  'metis:"Metis"'
  'momus:"Momus"'
)

# Forbidden verbose assignments — would indicate the source regression returned.
FORBIDDEN_VERBOSE=(
  'sisyphus:"Sisyphus - Ultraworker"'
  'sisyphus:"Sisyphus - ultraworker"'
  'hephaestus:"Hephaestus - Deep Agent"'
  'prometheus:"Prometheus - Plan Builder"'
  'atlas:"Atlas - Plan Executor"'
  'metis:"Metis - Plan Consultant"'
  'momus:"Momus - Plan Critic"'
)

for dist in "$DIST_MAIN" "$DIST_CLI"; do
  [[ -f "$dist" ]] || continue

  for expected in "${EXPECTED_PLAIN[@]}"; do
    # Input: `key:"value"`. Allow whitespace around the colon (Bun sometimes inserts a space).
    key=$(printf '%s' "$expected" | sed 's/:.*//')
    val=$(printf '%s' "$expected" | sed 's/.*:"//; s/"$//')
    pattern=$(printf '%s:\\s*"%s"' "$key" "$val")
    if ! grep -qE "$pattern" "$dist"; then
      echo "FAIL: expected plain assignment '$expected' missing from $dist"
      fail=1
    fi
  done

  for forbidden in "${FORBIDDEN_VERBOSE[@]}"; do
    key=$(printf '%s' "$forbidden" | sed 's/:.*//')
    val=$(printf '%s' "$forbidden" | sed 's/.*:"//; s/"$//')
    # Use fixed-string match on the value portion to avoid regex issues with parens/dashes.
    if grep -qF "$key" "$dist" && grep -qF "$val" "$dist"; then
      # Both key and value present — now check they are paired by looking for the assignment pattern
      pattern=$(printf '%s\\s*:\\s*"%s"' "$key" "$val")
      if grep -qE "$pattern" "$dist"; then
        echo "FAIL: verbose assignment '$forbidden' still present in $dist"
        fail=1
      fi
    fi
  done
done

if ! grep -qF 'normalizeAgentForPrompt' "$DIST_MAIN"; then
  echo "FAIL: normalizeAgentForPrompt missing from $DIST_MAIN (patch lost?)"
  fail=1
fi

if [[ "$fail" -eq 0 ]]; then
  echo "PASS: AGENT_DISPLAY_NAMES values are plain; verbose suffixes not emitted at runtime"
fi
exit "$fail"
