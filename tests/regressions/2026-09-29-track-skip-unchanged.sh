#!/usr/bin/env bash
set -euo pipefail

source_file="${OPENCODE_SNAPSHOT_SOURCE:-$HOME/src/opencode/packages/opencode/src/snapshot/index.ts}"
[[ -f "$source_file" ]] || { printf 'FAIL: missing snapshot source\n' >&2; exit 1; }

for required in 'tracked.length === 0 && untracked.length === 0' 'read-tree", "--empty' 'const content = text ?' 'read(target)) === content' 'args(["write-tree"])'; do
    if ! grep -Fq "$required" "$source_file"; then
        printf 'FAIL: unchanged snapshot guard missing: %s\n' "$required" >&2
        exit 1
    fi
done
printf 'PASS: unchanged index skip and authoritative tree source path present\n'
