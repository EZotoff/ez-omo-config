#!/usr/bin/env bash
set -o errexit
source "$(cd "$(dirname "$0")/.." && pwd)/helpers.sh"
tmpdir="$(mktemp -d)"; trap 'rm -rf "$tmpdir"' EXIT
cat > "$tmpdir/mock.sh" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$UNBOUND_PATCH_VARIABLE"
MOCK
output="$(bash "$tmpdir/mock.sh" 2>&1 || true)"
printf '%s\n' "$output" > "$tmpdir/output"
assert_no_grep "unbound variable" "$tmpdir/output" >"$tmpdir/assertion" 2>&1 || true
if grep -q 'FAIL: Pattern unexpectedly found.*unbound variable' "$tmpdir/assertion"; then
    echo "PROVED: unbound variable"
    exit 0
fi
echo "FAIL: unbound-variable sentinel not detected"
exit 1
