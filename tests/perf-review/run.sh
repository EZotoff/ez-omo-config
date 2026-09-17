#!/usr/bin/env bash
# tests/perf-review/run.sh
#
# Runs every tests/perf-review/bench-*.mjs benchmark with node and prints a
# summary table. This runner is INFORMATIONAL ONLY: it is intentionally NOT
# registered in the repository's aggregate test suite (the top-level script
# that chains every test), because latency numbers are machine-dependent and
# must not gate merges. Only completion (no throw) is required for exit 0.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

shopt -s nullglob
BENCHES=( "$SCRIPT_DIR"/bench-*.mjs )
shopt -u nullglob

if [[ ${#BENCHES[@]} -eq 0 ]]; then
    echo "perf-review: no bench-*.mjs files found in $SCRIPT_DIR" >&2
    exit 1
fi

printf '%-40s %12s %12s %12s %12s %10s\n' "BENCH" "P50(ms)" "P95(ms)" "P99(ms)" "MEAN(ms)" "ITERS"
FAILED=0

for bench_file in "${BENCHES[@]}"; do
    bench_name="$(basename "$bench_file")"
    if ! out="$(node "$bench_file" 2>&1)"; then
        echo "FAIL: benchmark threw: $bench_name" >&2
        echo "$out" >&2
        FAILED=$((FAILED + 1))
        continue
    fi
    # Each benchmark prints one JSON object per bench() call.
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        row="$(node -e '
            const r = JSON.parse(process.argv[1]);
            console.log(
              r.name.padEnd(40),
              r.p50.toFixed(4).padStart(12),
              r.p95.toFixed(4).padStart(12),
              r.p99.toFixed(4).padStart(12),
              r.mean.toFixed(4).padStart(12),
              String(r.iterations).padStart(10)
            );
        ' "$line")"
        printf '%s\n' "$row"
    done <<< "$out"
done

echo "----------------------------------------"
if [[ $FAILED -gt 0 ]]; then
    echo "perf-review: $FAILED benchmark(s) failed" >&2
    exit 1
fi
echo "perf-review: all ${#BENCHES[@]} benchmark(s) completed"
exit 0
