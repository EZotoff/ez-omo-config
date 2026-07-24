#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../helpers.sh"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

cat >"$TMP_ROOT/config.json" <<JSON
{"plugin":["file://$TMP_ROOT/path-A"]}
JSON
cat >"$TMP_ROOT/patch.md" <<PATCH
target_install_path: "$TMP_ROOT/path-B"
PATCH
cat >"$TMP_ROOT/mock.sh" <<'MOCK'
#!/usr/bin/env bash
runtime_path="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["plugin"][0].removeprefix("file://"))' "$1")"
runtime_path="$(grep '^target_install_path:' "$2" | cut -d: -f2- | tr -d ' "')"
echo "CHECKED: $runtime_path"
MOCK

bash "$TMP_ROOT/mock.sh" "$TMP_ROOT/config.json" "$TMP_ROOT/patch.md" >"$TMP_ROOT/output"
assert_no_grep "$TMP_ROOT/path-B" "$TMP_ROOT/output" >"$TMP_ROOT/assertion" 2>&1 || true
if grep -q 'FAIL: Pattern unexpectedly found.*path-B' "$TMP_ROOT/assertion"; then
    echo "KILL-PROVED: two-source assertion caught the overwrite"
    exit 0
fi
echo "KILL-BROKEN: missing two-source overwrite sentinel"
exit 1
