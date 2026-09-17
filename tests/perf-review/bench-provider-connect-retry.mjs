import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import { bench } from "./lib.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const registryPath = process.env.RETRY_REGISTRY_PATH
  ?? join(here, "..", "..", "configs", "retry-errors.json");
const registry = JSON.parse(readFileSync(registryPath, "utf8"));
const patterns = [];

for (const entry of registry.errors ?? []) {
  try {
    patterns.push(new RegExp(entry.pattern, "i"));
  } catch {
    process.stderr.write(`skipped malformed pattern: ${entry.pattern}\n`);
  }
}

const representativeError = "Monthly usage limit reached while contacting the provider gateway";
const result = bench(
  "provider-connect-retry.registry-match",
  () => patterns.find((pattern) => pattern.test(representativeError)),
  { iterations: 10_000 },
);

process.stdout.write(`${JSON.stringify(result)}\n`);
