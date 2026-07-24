#!/usr/bin/env bash
set -o errexit
source "$(cd "$(dirname "$0")/.." && pwd)/helpers.sh"
tmpdir="$(mktemp -d)"; trap 'rm -rf "$tmpdir"' EXIT
cat > "$tmpdir/mock.sh" <<'MOCK'
#!/usr/bin/env bash
TARGET="$1"
eval "\"$TARGET\" --version"
MOCK
output="$(bash "$tmpdir/mock.sh" "/tmp/path with spaces/fake-binary" 2>&1 || true)"
printf '%s\n' "$output" > "$tmpdir/output"
if assert_grep "No such file or directory\|command not found" "$tmpdir/output" >/dev/null 2>&1; then
    echo "PROVED: spaced-path shell error"; exit 0
fi
echo "FAIL: spaced-path shell-error sentinel not detected"; exit 1
