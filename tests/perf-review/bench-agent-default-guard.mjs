// tests/perf-review/bench-agent-default-guard.mjs
// Benchmarks the per-rewrite cost of agent-default-guard's readDefaultAgent():
// readFileSync + JSON.parse of a synthetic opencode.json-shaped config.
// readDefaultAgent is module-private, so this benches the identical operation
// (fs read + JSON.parse + default_agent extraction) against a synthetic config
// file sized like the real one. Picked up automatically by tests/perf-review/run.sh.

import { mkdtempSync, writeFileSync, rmSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { bench } from "./lib.mjs";

// Synthetic config object shaped like the live opencode.json: providers with
// model lists, plugin array, agent settings — enough bulk to be representative.
const providers = Object.fromEntries(
  ["google", "deepseek", "zai-coding-plan", "kimi-for-coding-oauth", "opencode-go", "anthropic", "openai", "mistral"].map((id, i) => [
    id,
    {
      npm: i > 1 ? "@ai-sdk/openai-compatible" : undefined,
      options: i > 1 ? { baseURL: `https://api.example.com/${id}/v1` } : undefined,
      models: Object.fromEntries(
        Array.from({ length: 8 }, (_, j) => [
          `${id}-model-${j}`,
          { name: `${id} model ${j}`, limit: { context: 128000, output: 8192 }, reasoning: j % 2 === 0 },
        ]),
      ),
    },
  ]),
);
const syntheticConfig = {
  theme: "opencode",
  default_agent: "Sisyphus",
  plugin: [
    "./provider-connect-retry.mjs",
    "./agent-default-guard.mjs",
    "./live-config-guard.mjs",
    "./aspect-dynamics.mjs",
    "./output-shaper.mjs",
    "./skill-nudger.mjs",
    "../../.opencode/plugin/clickable-links.ts",
    "../../.opencode/plugin/session-info.ts",
    "../../.opencode/plugin/git-safety.ts",
  ],
  enabled_providers: Object.keys(providers),
  provider: providers,
  agent: {
    build: { model: "zai-coding-plan/glm-5.3", prompt: "x".repeat(2048) },
    sisyphus: { model: "zai-coding-plan/glm-5.3", prompt: "y".repeat(2048) },
  },
  ui: { experimental: { inlineHint: true } },
};

const FIXTURES = mkdtempSync(join(tmpdir(), "bench-agent-default-guard-"));
const CONFIG = join(FIXTURES, "opencode.json");
writeFileSync(CONFIG, JSON.stringify(syntheticConfig));

function readDefaultAgent(configPath) {
  try {
    const cfg = JSON.parse(readFileSync(configPath, "utf8"));
    const agent = cfg.default_agent;
    return typeof agent === "string" && agent.trim().length > 0 ? agent.trim() : undefined;
  } catch {
    return undefined;
  }
}

const result = bench("agent-default-guard-readDefaultAgent", () => readDefaultAgent(CONFIG), {
  iterations: 10_000,
  warmup: 1_000,
});

rmSync(FIXTURES, { recursive: true, force: true });
console.log(JSON.stringify(result));
