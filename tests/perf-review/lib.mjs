// tests/perf-review/lib.mjs
// Minimal benchmark harness for server-plugin perf reviews.
// No dependencies beyond node:perf_hooks. The caller passes a deterministic
// synthetic-input workload (fn); warmup iterations are excluded from stats.

import { performance } from "node:perf_hooks";

function percentile(sorted, p) {
  const idx = Math.min(sorted.length - 1, Math.floor((p / 100) * sorted.length));
  return sorted[idx];
}

/**
 * Benchmark `fn` and return latency percentiles in milliseconds.
 * @param {string} name - benchmark label
 * @param {(i: number) => unknown} fn - deterministic workload; receives the iteration index
 * @param {{ iterations?: number, warmup?: number }} [opts]
 * @returns {{ name: string, p50: number, p95: number, p99: number, mean: number, iterations: number }}
 */
export function bench(name, fn, { iterations = 10000, warmup = 1000 } = {}) {
  for (let i = 0; i < warmup; i++) {
    fn(i);
  }

  const samples = new Array(iterations);
  let total = 0;
  for (let i = 0; i < iterations; i++) {
    const t0 = performance.now();
    fn(i);
    const dt = performance.now() - t0;
    samples[i] = dt;
    total += dt;
  }

  samples.sort((a, b) => a - b);
  return {
    name,
    p50: percentile(samples, 50),
    p95: percentile(samples, 95),
    p99: percentile(samples, 99),
    mean: total / iterations,
    iterations,
  };
}
