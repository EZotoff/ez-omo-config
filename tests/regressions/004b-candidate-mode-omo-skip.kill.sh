#!/usr/bin/env bash
set -o errexit
source "$(cd "$(dirname "$0")/.." && pwd)/helpers.sh"
tmpdir="$(mktemp -d)"; trap 'rm -rf "$tmpdir"' EXIT
cat > "$tmpdir/mock.sh" <<'MOCK'
#!/usr/bin/env bash
echo "MISSING-TARGET omo--candidate-fixture"
MOCK
bash "$tmpdir/mock.sh" /nonexistent/fake-binary > "$tmpdir/output"
assert_no_grep "\(STALE\|MISSING-TARGET\).*omo--" "$tmpdir/output" >"$tmpdir/assertion" 2>&1 || true
if grep -q 'FAIL: Pattern unexpectedly found.*omo--' "$tmpdir/assertion"; then
    echo "PROVED: MISSING-TARGET omo--candidate-fixture"
    exit 0
fi
echo "FAIL: candidate OMO sentinel not detected"
exit 1
