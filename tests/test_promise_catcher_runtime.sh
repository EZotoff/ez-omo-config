#!/usr/bin/env bash

# Promise-catcher runtime harness regression wrapper
# Runs all harness test cases and exits 0 if all pass

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "$SCRIPT_DIR/helpers.sh" ]]; then
    source "$SCRIPT_DIR/helpers.sh"
fi

HARNESS="$SCRIPT_DIR/promise-catcher/harness.mjs"

if ! node "$HARNESS"; then
    echo "FAIL: promise-catcher harness"
    exit 1
fi

echo "PASS: promise-catcher harness"
exit 0
