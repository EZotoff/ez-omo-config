#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "$0")/../.." && pwd)"
source_repo="${OPENCODE_SOURCE_REPO:-$HOME/src/opencode}"
fixture="$(mktemp)"
trap 'rm -f "$fixture"' EXIT
GIT_MASTER=1 git -C "$source_repo" show 48eedf9406:packages/opencode/src/snapshot/index.ts > "$fixture"
if OPENCODE_SNAPSHOT_SOURCE="$fixture" bash "$repo/tests/regressions/2026-09-29-diff-context-bound.sh" >/dev/null 2>&1; then
    printf 'FAIL: baseline diff was not detected\n' >&2
    exit 1
fi
printf 'PASS: unpatched diff fails the regression\n'
