#!/usr/bin/env bash
set -o errexit
source "$(cd "$(dirname "$0")/.." && pwd)/helpers.sh"
tmpdir="$(mktemp -d)"; trap 'rm -rf "$tmpdir"' EXIT
touch "$tmpdir/file1.ts" "$tmpdir/file3.ts"
cat > "$tmpdir/mock.sh" <<'MOCK'
#!/usr/bin/env bash
target_file="file1.ts,file2.ts,file3.ts"
first_target_file="${target_file%%,*}"
[[ -f "$ROOT/$first_target_file" ]] && echo "APPLIED multi-file-fixture"
MOCK
ROOT="$tmpdir" bash "$tmpdir/mock.sh" > "$tmpdir/output"
assert_grep "MISSING-TARGET.*multi-file-fixture" "$tmpdir/output" >"$tmpdir/assertion" 2>&1 || true
if grep -q 'FAIL: Pattern not found.*multi-file-fixture' "$tmpdir/assertion"; then
    echo "PROVED: missing MISSING-TARGET multi-file-fixture"
    exit 0
fi
echo "FAIL: first-file-only failure sentinel not detected"
exit 1
