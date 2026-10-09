#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "$0")/../.." && pwd)"
source_file="${OPENCODE_PROCESSOR_SOURCE:-$HOME/src/opencode-wt-stall/packages/opencode/src/session/processor.ts}"
[[ -f "$source_file" ]] || { printf 'FAIL: missing processor source\n' >&2; exit 1; }
fixture="$(mktemp)"
trap 'rm -f "$fixture"' EXIT
# Fixture: processor.ts with the tracking step's local-tool registration
# removed (set never gains IDs → exemption dead → regression must fail).
perl -pe 's/localTools\.add\(event\.id\)/void event.id/' "$source_file" > "$fixture"

if OPENCODE_PROCESSOR_SOURCE="$fixture" bash "$repo/tests/regressions/2026-10-09-local-tool-stall-exemption.sh" >/dev/null 2>&1; then
    printf 'FAIL: regression did not detect missing local-tool registration\n' >&2
    exit 1
fi
printf 'PASS: removing local-tool registration makes regression fail\n'
