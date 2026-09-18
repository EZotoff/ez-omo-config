#!/usr/bin/env bash
# Smoke: opencode--bash-lifecycle-group-cleanup (plan: patch-provenance T6).
#
# Reuses the paired regression tests/regressions/bash-group-cleanup-timeout.sh
# (which accepts OPENCODE_BIN and drives the live binary through `opencode run`)
# against the target binary, and records the verdict in the per-SHA store.
# Model-unreachable failures are recorded as SKIP, not FAIL.
# Usage: smoke-bash-lifecycle.sh [binary] (default: live binary)
set -euo pipefail
SMOKE_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SMOKE_DIR/lib-smoke.sh"

BIN="${1:-$HOME/.opencode/bin/opencode}"
SMOKE_ID="bash-lifecycle-group-cleanup"
REGRESSION="$SMOKE_DIR/../regressions/bash-group-cleanup-timeout.sh"

if ! smoke_require_binary "$BIN"; then
    sha="$(smoke_sha256 "$BIN" 2>/dev/null || echo unknown)"
    smoke_record "$sha" "$SMOKE_ID" "FAIL" "binary missing or not executable: $BIN"
    echo "FAIL: binary missing or not executable: $BIN"
    exit 1
fi
if [[ ! -f "$REGRESSION" ]]; then
    smoke_record "$(smoke_sha256 "$BIN")" "$SMOKE_ID" "FAIL" "regression script missing: $REGRESSION"
    echo "FAIL: regression script missing: $REGRESSION"
    exit 1
fi

BIN_SHA="$(smoke_sha256 "$BIN")"

if [[ "${SMOKE_FORCE:-0}" != "1" ]] && smoke_already_passing "$BIN_SHA" "$SMOKE_ID"; then
    echo "SKIP-RERUN: $SMOKE_ID already PASS for sha ${BIN_SHA:0:12} (set SMOKE_FORCE=1 to rerun)"
    exit 0
fi

# --- run the paired regression against the target binary ---------------------
# OPENCODE_BIN honored as-is (no modification to the regression script needed).
WORK="$(mktemp -d "${TMPDIR:-/tmp}/opencode/smoke-lifecycle.XXXXXX")"
trap 'rm -rf "$WORK"; smoke_cleanup' EXIT

set +e
OPENCODE_BIN="$BIN" bash "$REGRESSION" > "$WORK/out.log" 2>&1
RC=$?
set -e

cat "$WORK/out.log"

UNREACHABLE_RE='(quota|rate.?limit|unreachable|connection (refused|error|failed)|ECONNRESET|ECONNREFUSED|network error|authentication|unauthorized|no such model)'
if [[ $RC -ne 0 ]] && grep -Eqi "$UNREACHABLE_RE" "$WORK/out.log"; then
    smoke_record "$BIN_SHA" "$SMOKE_ID" "SKIP" \
        "model/provider unreachable during regression run (binary ${BIN_SHA:0:12})"
    echo "SKIP: model unreachable / provider error"
    exit 0
fi

if [[ $RC -eq 0 ]]; then
    smoke_record "$BIN_SHA" "$SMOKE_ID" "PASS" \
        "regression bash-group-cleanup-timeout.sh green (binary ${BIN_SHA:0:12})"
    echo "PASS: bash-lifecycle regression green against target binary"
    exit 0
fi

smoke_record "$BIN_SHA" "$SMOKE_ID" "FAIL" \
    "regression bash-group-cleanup-timeout.sh rc=$RC (binary ${BIN_SHA:0:12})"
echo "FAIL: regression rc=$RC"
exit 1
