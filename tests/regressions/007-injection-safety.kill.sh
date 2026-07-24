#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../helpers.sh"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

cat >"$TMP_ROOT/mock.sh" <<'MOCK'
#!/usr/bin/env bash
pattern="$1"
text="$2"
python3 - <<PY
import re
text = '''$text'''
re.search('''$pattern''', text)
PY
MOCK

PAYLOAD="__INJECTION_TEST__''', text); import os; os.system('echo PWNED'); #"
bash "$TMP_ROOT/mock.sh" "$PAYLOAD" 'safe fixture' >"$TMP_ROOT/output" 2>&1 || true
assert_no_grep 'PWNED' "$TMP_ROOT/output" >"$TMP_ROOT/assertion" 2>&1 || true
if grep -q 'FAIL: Pattern unexpectedly found.*PWNED' "$TMP_ROOT/assertion"; then
    echo "KILL-PROVED: injection assertion caught executed payload"
    exit 0
fi
echo "KILL-BROKEN: missing injection execution sentinel"
exit 1
