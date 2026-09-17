// tests/perf-review/bench-agent-default-guard.mjs
// Benchmarks the REAL agent-default-guard chat.message hook: config read +
// registry lookup + rewrite, against a synthetic opencode.json and a fake
// agent registry. Picked up automatically by tests/perf-review/run.sh.

import { mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { asyncBench } from "./lib.mjs";

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
const LOG = join(FIXTURES, "agent-default-guard.log");
writeFileSync(CONFIG, JSON.stringify(syntheticConfig));

// Route the plugin's config read and log write away from live machine state.
globalThis.__agentDefaultGuardTestPaths = { config: CONFIG, log: LOG };

const PLUGIN_PATH = new URL("../../configs/opencode/agent-default-guard.mjs", import.meta.url).pathname;
const { default: buildPlugin } = await import(PLUGIN_PATH);

// Fake registry: build is a hidden subagent (OMO applied) and Sisyphus is the
// visible primary default, so the hook takes the rewrite path.
const agents = [
  { name: "build", mode: "subagent", hidden: true },
  { name: "Sisyphus", mode: "primary", hidden: false },
];
const ctx = { client: { app: { async agents() { return { data: agents }; } } } };
const hooks = await buildPlugin(ctx);
const hook = hooks["chat.message"];

const result = await asyncBench(
  "agent-default-guard.chat.message",
  () =>
    hook(
      { sessionID: "bench-session", agent: "build" },
      { message: { id: "msg-1", agent: "build" }, parts: [] },
    ),
  { iterations: 10_000, warmup: 1_000 },
);

rmSync(FIXTURES, { recursive: true, force: true });
console.log(JSON.stringify(result));
