#!/usr/bin/env bash
# tests/perf-review/run.sh
#
# Runs every tests/perf-review/bench-*.mjs benchmark with node and prints a
# summary table. This runner is INFORMATIONAL ONLY: it is intentionally NOT
# registered in the repository's aggregate test suite (the top-level script
# that chains every test), because latency numbers are machine-dependent and
# must not gate merges. Only completion (no throw) is required for exit 0.
#
# Each benchmark may print one JSON object per line, or one JSON array of
# objects on a line; both shapes are rendered. Non-JSON lines (e.g. stderr
# diagnostics) are skipped.

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
    # Render each line: a JSON object, or a JSON array of objects. Anything
    # else (blank lines, stderr diagnostics) is skipped.
    while IFS= read -r line; do
        if [[ -z "$line" ]]; then
            continue
        fi
        row="$(printf '%s' "$line" | node -e '
            let raw = "";
            process.stdin.setEncoding("utf8");
            process.stdin.on("data", (chunk) => { raw += chunk; });
            process.stdin.on("end", () => {
              let parsed;
              try { parsed = JSON.parse(raw); } catch { return; }
              const items = Array.isArray(parsed) ? parsed : [parsed];
              for (const r of items) {
                if (!r || typeof r !== "object" || typeof r.name !== "string" || typeof r.p50 !== "number") continue;
                console.log(
                  r.name.padEnd(40),
                  Number(r.p50).toFixed(4).padStart(12),
                  Number(r.p95).toFixed(4).padStart(12),
                  Number(r.p99).toFixed(4).padStart(12),
                  Number(r.mean).toFixed(4).padStart(12),
                  String(r.iterations).padStart(10)
                );
              }
            });
        ')"
        if [[ -n "$row" ]]; then
            printf '%s\n' "$row"
        fi
    done <<< "$out"
done

echo "----------------------------------------"
if [[ $FAILED -gt 0 ]]; then
    echo "perf-review: $FAILED benchmark(s) failed" >&2
    exit 1
fi
echo "perf-review: all ${#BENCHES[@]} benchmark(s) completed"
exit 0
