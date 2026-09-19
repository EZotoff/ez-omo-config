#!/usr/bin/env bash
# Smoke: opencode--bash-lifecycle-group-cleanup (plan: patch-provenance T6).
#
# Reuses the paired regression tests/regressions/bash-group-cleanup-timeout.sh
# (which accepts OPENCODE_BIN and drives the live binary through `opencode run`)
# against the target binary, and records the verdict in the per-SHA store.
# Model-unreachable failures are recorded as SKIP, not FAIL.
# Usage: smoke-bash-lifecycle.sh [--force] [binary] (default: live binary)
set -euo pipefail
SMOKE_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SMOKE_DIR/lib-smoke.sh"

FORCE=0
POSIX_ARGS=()
for arg in "$@"; do
    case "$arg" in
        --force) FORCE=1 ;;
        *) POSIX_ARGS+=("$arg") ;;
    esac
done
BIN="${POSIX_ARGS[0]:-$HOME/.opencode/bin/opencode}"
SMOKE_ID="bash-lifecycle-group-cleanup"
REGRESSION="$SMOKE_DIR/../regressions/bash-group-cleanup-timeout.sh"

if ! smoke_require_binary "$BIN"; then
    sha="$(smoke_sha256 "$BIN" 2>/dev/null || echo unknown)"
    smoke_record "$sha" "$SMOKE_ID" "FAIL" "binary missing or not executable: $BIN" "$BIN"
    echo "FAIL: binary missing or not executable: $BIN"
    exit 1
fi
if [[ ! -f "$REGRESSION" ]]; then
    smoke_record "$(smoke_sha256 "$BIN")" "$SMOKE_ID" "FAIL" "regression script missing: $REGRESSION" "$REGRESSION"
    echo "FAIL: regression script missing: $REGRESSION"
    exit 1
fi

BIN_SHA="$(smoke_sha256 "$BIN")"

if [[ "${SMOKE_FORCE:-0}" != "1" && $FORCE -ne 1 ]] && smoke_already_passing "$BIN_SHA" "$SMOKE_ID";
    then
    echo "SKIP-RERUN: $SMOKE_ID already PASS for sha ${BIN_SHA:0:12} (set SMOKE_FORCE=1 or pass --force to rerun)"
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


# Persist the log BEFORE the EXIT trap deletes $WORK — evidence paths in the
# result store must survive (smoke_record stores them long-term).
EVID_DIR="$SMOKE_DIR/../../.sisyphus/evidence"
mkdir -p "$EVID_DIR"
EVID_LOG="$EVID_DIR/smoke-bash-lifecycle-$(date +%Y%m%d-%H%M%S).log"
cp "$WORK/out.log" "$EVID_LOG"


UNREACHABLE_RE='(quota|rate.?limit|unreachable|connection (refused|error|failed)|ECONNRESET|ECONNREFUSED|network error|authentication|unauthorized|no such model)'
if [[ $RC -ne 0 ]] && grep -Eqi "$UNREACHABLE_RE" "$WORK/out.log"; then
smoke_record "$BIN_SHA" "$SMOKE_ID" "SKIP" \
        "model/provider unreachable during regression run (binary ${BIN_SHA:0:12})" \
        "$EVID_LOG"
    echo "SKIP: model unreachable / provider error"
    exit 0
fi

if [[ $RC -eq 0 ]]; then
smoke_record "$BIN_SHA" "$SMOKE_ID" "PASS" \
        "regression bash-group-cleanup-timeout.sh green (binary ${BIN_SHA:0:12})" \
        "$EVID_LOG"
    echo "PASS: bash-lifecycle regression green against target binary"
    exit 0
fi

smoke_record "$BIN_SHA" "$SMOKE_ID" "FAIL" \
    "regression bash-group-cleanup-timeout.sh rc=$RC (binary ${BIN_SHA:0:12})" \
    "$EVID_LOG"
echo "FAIL: regression rc=$RC"
exit 1
