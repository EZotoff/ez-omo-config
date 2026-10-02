#!/usr/bin/env bash
set -euo pipefail

source_file="${OPENCODE_SNAPSHOT_SOURCE:-$HOME/src/opencode/packages/opencode/src/snapshot/index.ts}"
[[ -f "$source_file" ]] || { printf 'FAIL: missing snapshot source\n' >&2; exit 1; }

# Status gate: structural greps only enforce while the patch entry is active.
# Kill variants and explicit fixture runs set OPENCODE_SNAPSHOT_SOURCE, so the
# gate yields and the full assertion set (and its polarity) still runs.
repo="$(cd "$(dirname "$0")/../.." && pwd)"
if [[ -z "${OPENCODE_SNAPSHOT_SOURCE:-}" ]]; then
    entry="$repo/.sisyphus/patches/opencode--snapshot-track-skip-unchanged.md"
    status="$(grep -m1 -oP '^status:\s*"\K[^"]+' "$entry" 2>/dev/null || true)"
    if [[ "$status" != "active" ]]; then
        printf 'SKIP (deferred): patch opencode--snapshot-track-skip-unchanged status=%s — structural greps re-arm when the entry flips to active\n' "${status:-unknown}"
        exit 0
    fi
fi

for required in 'tracked.length === 0 && untracked.length === 0' 'read-tree", "--empty' 'const content = text ?' 'read(target)) === content' 'args(["write-tree"])'; do
    if ! grep -Fq "$required" "$source_file"; then
        printf 'FAIL: unchanged snapshot guard missing: %s\n' "$required" >&2
        exit 1
    fi
done
printf 'PASS: unchanged index skip and authoritative tree source path present\n'
