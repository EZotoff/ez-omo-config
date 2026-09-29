#!/usr/bin/env bash
set -euo pipefail

source_file="${OPENCODE_SNAPSHOT_SOURCE:-$HOME/src/opencode/packages/opencode/src/snapshot/index.ts}"
[[ -f "$source_file" ]] || { printf 'FAIL: missing snapshot source\n' >&2; exit 1; }

for required in 'OPENCODE_MAX_PATCH_BYTES' 'configured : 262144' 'Number.MAX_SAFE_INTEGER : 3' 'hunks.push(hunk)' 'hit.oversized ? headerOnly'; do
    if ! grep -Fq "$required" "$source_file"; then
        printf 'FAIL: bounded diff missing: %s\n' "$required" >&2
        exit 1
    fi
done
printf 'PASS: bounded diff source path present\n'
