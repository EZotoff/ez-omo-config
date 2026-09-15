// tests/perf-review/bench-template.mjs
// Template for plugin benchmarks. Copy this file, swap the synthetic input
// and workload for the plugin under test (e.g. scoreAspects, signal
// detection, model gating), and run.sh picks it up automatically.

import { bench } from "./lib.mjs";

// Deterministic synthetic input: a fixed message window (no randomness,
// no network, no live server) shaped like the contexts the plugins scan.
const PHRASES = ["error", "failed", "timeout", "exception", "traceback"];
const syntheticMessages = Array.from({ length: 200 }, (_, i) => ({
  id: `msg-${i}`,
  role: i % 2 === 0 ? "user" : "assistant",
  text: `turn ${i}: ${PHRASES[i % PHRASES.length]} while npm run dev exited with code 1`,
}));

const result = bench("template-phrase-scan", (i) => {
  let hits = 0;
  const needle = PHRASES[i % PHRASES.length];
  for (const msg of syntheticMessages) {
    if (msg.text.includes(needle)) hits++;
  }
  return hits;
});

console.log(JSON.stringify(result));
