#!/usr/bin/env bash
set -o errexit
source "$(cd "$(dirname "$0")/.." && pwd)/helpers.sh"
tmpdir="$(mktemp -d)"; trap 'rm -rf "$tmpdir"' EXIT
cat > "$tmpdir/retired.md" <<'PATCH'
status: "retired"
patch_id: "retired-fixture"
PATCH
cat > "$tmpdir/mock.sh" <<'MOCK'
#!/usr/bin/env bash
echo "STALE retired-fixture"
MOCK
bash "$tmpdir/mock.sh" > "$tmpdir/output"
assert_no_grep "STALE.*retired-fixture" "$tmpdir/output" >"$tmpdir/assertion" 2>&1 || true
if grep -q 'FAIL: Pattern unexpectedly found.*retired-fixture' "$tmpdir/assertion"; then
    echo "PROVED: STALE retired-fixture"
    exit 0
fi
echo "FAIL: retired-patch sentinel not detected"
exit 1
