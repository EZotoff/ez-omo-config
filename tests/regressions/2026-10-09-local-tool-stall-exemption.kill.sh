#!/usr/bin/env bash
# Kill variant: feed the regression test a fixture MISSING the local-tool
# tracking block. The test MUST fail (non-zero exit). If it passes, the
# assertions are dead (no polarity) and this kill script fails instead.
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
fixture="$(mktemp)"
trap 'rm -f "$fixture"' EXIT

cat > "$fixture" <<'EOF'
// fixture: processor.ts WITHOUT the local-tool stall exemption fix
export const watch = "watchdog"
EOF

output="$(OPENCODE_PROCESSOR_SOURCE="$fixture" bash "$here/2026-10-09-local-tool-stall-exemption.sh" 2>&1)"
rc=$?

if [[ $rc -eq 0 ]]; then
    printf 'KILL-FAIL: regression test passed against fixture missing the tracking step — assertions have no polarity\n%s\n' "$output" >&2
    exit 1
fi

printf 'KILL-PASS: test correctly fails against fixture missing the tracking step (exit %d)\n' "$rc"
exit "$rc"
