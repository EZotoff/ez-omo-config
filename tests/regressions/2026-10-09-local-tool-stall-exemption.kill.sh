#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "$0")/../.." && pwd)"
# Base source MUST carry the tracking step so that removing it is the ONLY reason
# the main test fails. The fix lives in the stall worktree; the live ~/src/opencode
# tree does not carry the markers yet (patch entry not registered).
base="${OPENCODE_PROCESSOR_SOURCE:-$HOME/src/opencode-wt-stall/packages/opencode/src/session/processor.ts}"
[[ -f "$base" ]] || { printf 'FAIL: missing base processor source: %s\n' "$base" >&2; exit 1; }
fixture="$(mktemp)"
trap 'rm -f "$fixture"' EXIT
perl -pe 's/if \(event\.type === "tool-call" && !event\.providerExecuted\) localTools\.add\(event\.id\)/void event.id/' "$base" > "$fixture"

if OPENCODE_PROCESSOR_SOURCE="$fixture" bash "$repo/tests/regressions/2026-10-09-local-tool-stall-exemption.sh" >/dev/null 2>&1; then
    printf 'FAIL: regression did not detect missing local-tool tracking step\n' >&2
    exit 1
fi
printf 'PASS: removing local-tool tracking step makes regression fail\n'
