#!/usr/bin/env bash
# Kill variant: feed the regression test a fixture MISSING the local-tool
# tracking step. The test MUST fail (non-zero exit). If it passes, the
# assertions are dead (no polarity) and this kill script fails.
# Exits 0 when polarity is proven (matches tests/run_regressions.sh, which
# counts a non-zero kill script as "kill-tests broken").
set -euo pipefail

repo="$(cd "$(dirname "$0")/../.." && pwd)"
fixture="$(mktemp)"
trap 'rm -f "$fixture"' EXIT

cat > "$fixture" <<'EOF'
// fixture: processor.ts WITHOUT the local-tool stall exemption tracking step
export const watch = "watchdog"
EOF

if OPENCODE_PROCESSOR_SOURCE="$fixture" bash "$repo/tests/regressions/2026-10-09-local-tool-stall-exemption.sh" >/dev/null 2>&1; then
    printf 'FAIL: regression did not detect missing local-tool tracking step\n' >&2
    exit 1
fi
printf 'PASS: removing local-tool tracking makes regression fail\n'
