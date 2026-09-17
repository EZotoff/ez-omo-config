// tests/perf-review/bench-logging-hotpath.mjs
// Benchmarks the module-logger write hot path shared by the config-layer
// plugins: statSync size check + appendFileSync against a temp log file.
// The real logging modules resolve a fixed ~/.config path with no test
// override, so this replicates the exact sequence against a temp file.

import { appendFileSync, mkdtempSync, rmSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { bench } from "./lib.mjs";

const FIXTURES = mkdtempSync(join(tmpdir(), "bench-logging-hotpath-"));
const LOG_PATH = join(FIXTURES, "plugin.log");
const LOG_MAX_BYTES = 2 * 1024 * 1024;

const result = bench(
  "logging-hotpath.stat-append",
  () => {
    const line = `[${new Date().toISOString()}] [plugin] [info] hook=chat.params dur_ms=0.00`;
    try {
      const stat = statSync(LOG_PATH);
      if (stat.size > LOG_MAX_BYTES) {
        // Rotation branch is not exercised at benchmark scale (10k lines < 2 MB).
      }
    } catch {
      // file doesn't exist yet — nothing to rotate
    }
    appendFileSync(LOG_PATH, `${line}\n`, "utf8");
  },
  { iterations: 10_000, warmup: 1_000 },
);

rmSync(FIXTURES, { recursive: true, force: true });
console.log(JSON.stringify(result));
