#!/usr/bin/env bash
set -euo pipefail

source_file="${OPENCODE_SNAPSHOT_SOURCE:-$HOME/src/opencode/packages/opencode/src/snapshot/index.ts}"
[[ -f "$source_file" ]] || { printf 'FAIL: missing snapshot source\n' >&2; exit 1; }

# Status gate: structural greps only enforce while the patch entry is active.
# Kill variants and explicit fixture runs set OPENCODE_SNAPSHOT_SOURCE, so the
# gate yields and the full assertion set (and its polarity) still runs.
repo="$(cd "$(dirname "$0")/../.." && pwd)"
if [[ -z "${OPENCODE_SNAPSHOT_SOURCE:-}" ]]; then
    entry="$repo/.sisyphus/patches/opencode--diff-context-bound.md"
    status="$(grep -m1 -oP '^status:\s*"\K[^"]+' "$entry" 2>/dev/null || true)"
    if [[ "$status" != "active" ]]; then
        printf 'SKIP (deferred): patch opencode--diff-context-bound status=%s — structural greps re-arm when the entry flips to active\n' "${status:-unknown}"
        exit 0
    fi
fi

for required in 'OPENCODE_MAX_PATCH_BYTES' 'configured : 262144' 'Number.MAX_SAFE_INTEGER : 3' 'hunks.push(hunk)' 'cat-file", "--batch-check' '> diff truncated (OPENCODE_MAX_PATCH_BYTES exceeded; not appliable)' '!text || hit.oversized ? headerOnly'; do
    if ! grep -Fq "$required" "$source_file"; then
        printf 'FAIL: bounded diff missing: %s\n' "$required" >&2
        exit 1
    fi
done
printf 'PASS: bounded diff source path present\n'
