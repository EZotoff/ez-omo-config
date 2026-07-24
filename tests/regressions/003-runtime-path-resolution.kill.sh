#!/usr/bin/env bash
set -o errexit
source "$(cd "$(dirname "$0")/.." && pwd)/helpers.sh"
tmpdir="$(mktemp -d)"; trap 'rm -rf "$tmpdir"' EXIT
mkdir -p "$tmpdir/config-runtime" "$tmpdir/wrong-runtime"
printf 'PATCH_PRESENT\n' > "$tmpdir/config-runtime/file.ts"
cat > "$tmpdir/mock.sh" <<'MOCK'
#!/usr/bin/env bash
[[ -f "$TARGET_INSTALL_PATH/file.ts" ]] || echo "MISSING-TARGET runtime-path-fixture"
MOCK
TARGET_INSTALL_PATH="$tmpdir/wrong-runtime" bash "$tmpdir/mock.sh" > "$tmpdir/output"
assert_no_grep "MISSING-TARGET.*runtime-path-fixture" "$tmpdir/output" >"$tmpdir/assertion" 2>&1 || true
if grep -q 'FAIL: Pattern unexpectedly found.*runtime-path-fixture' "$tmpdir/assertion"; then
    echo "PROVED: MISSING-TARGET runtime-path-fixture"
    exit 0
fi
echo "FAIL: wrong-runtime-path sentinel not detected"
exit 1
