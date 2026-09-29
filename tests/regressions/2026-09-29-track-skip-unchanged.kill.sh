#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "$0")/../.." && pwd)"
source_repo="${OPENCODE_SOURCE_REPO:-$HOME/src/opencode}"
fixture="$(mktemp)"
trap 'rm -f "$fixture"' EXIT
GIT_MASTER=1 git -C "$source_repo" show a73db3c331:packages/opencode/src/snapshot/index.ts > "$fixture"
if OPENCODE_SNAPSHOT_SOURCE="$fixture" bash "$repo/tests/regressions/2026-09-29-track-skip-unchanged.sh" >/dev/null 2>&1; then
    printf 'FAIL: baseline track was not detected\n' >&2
    exit 1
fi
printf 'PASS: pre-P3 track fails the regression\n'
