#!/usr/bin/env bash
# lib-patchset.sh — shared helpers for patch-set provenance tooling.
#
# Sourced by tests/test_patch_lockfile.sh, scripts/build-and-install-opencode.sh,
# and scripts/build-and-install-omo.sh. Provides lockfile loading, commit
# ancestry checks, and build-receipt read/write.
#
# Usage: source scripts/lib-patchset.sh   (after set -euo pipefail)

# Default source repo for the opencode dependency (override: OPENCODE_SRC).
OPENCODE_SRC="${OPENCODE_SRC:-$HOME/src/opencode}"

# Receipt store — deliberately OUTSIDE ~/.opencode/bin/ (the replaceable
# artifact) per the patch-provenance plan (receipts must survive swaps).
RECEIPT_DIR="${RECEIPT_DIR:-$HOME/.local/share/opencode/builds}"

# lockfile_load <file> — parse and structurally sanity-check a patch-set
# lockfile. Prints normalized patch lines: "<patch_id>\t<kind>\t<sha>..." is
# NOT used; callers use jq/python on the file directly. Here we only assert
# the file parses and has the required top-level fields.
lockfile_load() {
    local file="$1"
    [[ -f "$file" ]] || { echo "lockfile_load: no such lockfile: $file" >&2; return 1; }
    python3 - "$file" <<'PYEOF'
import json, sys
path = sys.argv[1]
try:
    data = json.load(open(path))
except Exception as exc:
    print(f"lockfile_load: JSON parse error in {path}: {exc}", file=sys.stderr)
    sys.exit(1)
required = ("schema_version", "dependency", "upstream_version", "upstream_base",
            "generation", "canonical_ref", "patches")
missing = [k for k in required if k not in data]
if missing:
    print(f"lockfile_load: missing top-level fields in {path}: {', '.join(missing)}", file=sys.stderr)
    sys.exit(1)
if not isinstance(data["patches"], list) or not data["patches"]:
    print(f"lockfile_load: 'patches' must be a non-empty array in {path}", file=sys.stderr)
    sys.exit(1)
PYEOF
}

# commit_exists <repo> <sha> — true iff <sha> resolves to a commit object.
commit_exists() {
    local repo="$1" sha="$2"
    git -C "$repo" cat-file -e "$sha^{commit}" 2>/dev/null
}

# commit_is_ancestor <repo> <sha> <ancestor-of> — true iff <sha> is an
# ancestor of <ancestor-of> (both must be commits).
commit_is_ancestor() {
    local repo="$1" sha="$2" head="$3"
    git -C "$repo" merge-base --is-ancestor "$sha" "$head" 2>/dev/null
}

# receipt_write <binary_sha256> <json-fields...> — write a build receipt.
# Extra args are pre-formatted JSON fragment strings (already comma-separated
# key:value pairs) merged into the standard envelope.
receipt_write() {
    local bin_sha="$1"; shift
    local extra="${1:-}"
    mkdir -p "$RECEIPT_DIR"
    local receipt="$RECEIPT_DIR/$bin_sha.json"
    local timestamp
    timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    if [[ -n "$extra" ]]; then
        printf '{"binary_sha256":"%s","timestamp":"%s",%s}\n' "$bin_sha" "$timestamp" "$extra" > "$receipt"
    else
        printf '{"binary_sha256":"%s","timestamp":"%s"}\n' "$bin_sha" "$timestamp" > "$receipt"
    fi
    echo "$receipt"
}

# receipt_read <binary_sha256> [key] — print the receipt JSON (or one field's
# value) for a binary hash; rc 1 if no receipt exists.
receipt_read() {
    local bin_sha="$1" key="${2:-}"
    local receipt="$RECEIPT_DIR/$bin_sha.json"
    [[ -f "$receipt" ]] || return 1
    if [[ -n "$key" ]]; then
        python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get(sys.argv[2],""))' "$receipt" "$key"
    else
        cat "$receipt"
    fi
}
