#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "$0")/../.." && pwd)"
source_file="${OPENCODE_PROCESSOR_SOURCE:-$HOME/src/opencode/packages/opencode/src/session/processor.ts}"
[[ -f "$source_file" ]] || { printf 'FAIL: missing processor source\n' >&2; exit 1; }
fixture="$(mktemp)"
trap 'rm -f "$fixture"' EXIT
perl -pe 's/inFlightQuestions\.add\(value\.id\)/void value.id/' "$source_file" > "$fixture"

if OPENCODE_PROCESSOR_SOURCE="$fixture" bash "$repo/tests/regressions/2026-09-28-question-stream-stall.sh" >/dev/null 2>&1; then
    printf 'FAIL: regression did not detect missing question registration\n' >&2
    exit 1
fi
printf 'PASS: removing question registration makes regression fail\n'
