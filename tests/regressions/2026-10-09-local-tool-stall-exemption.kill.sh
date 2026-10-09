#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "$0")/../.." && pwd)"
source_file="${OPENCODE_PROCESSOR_SOURCE:-$HOME/src/opencode/packages/opencode/src/session/processor.ts}"
[[ -f "$source_file" ]] || { printf 'FAIL: missing processor source\n' >&2; exit 1; }
fixture="$(mktemp)"
trap 'rm -f "$fixture"' EXIT
perl -pe 's/^\s*(if \(event\.type === "tool-call" && !event\.providerExecuted\) localTools\.add\(event\.id\))\s*$/void 0 \/\/ $1 removed/' "$source_file" > "$fixture"

if OPENCODE_PROCESSOR_SOURCE="$fixture" bash "$repo/tests/regressions/2026-10-09-local-tool-stall-exemption.sh" >/dev/null 2>&1; then
    printf 'FAIL: regression did not detect missing local tool tracking\n' >&2
    exit 1
fi
printf 'PASS: removing local tool tracking makes regression fail\n'
