// tests/perf-review/bench-output-shaper.mjs
// Benchmark the synchronous provider/model gate used before the resume API call.

import { getClampOptions, isTargetModel } from "../../configs/opencode/output-shaper/model-gating.mjs";
import { bench } from "./lib.mjs";

const PROVIDER_MODEL_MATRIX = [
  ["zai-coding-plan", "glm-5.3"],
  ["kimi-for-coding-oauth", "kimi-for-coding"],
  ["kimi-for-coding-oauth", "k3"],
  ["openai", "gpt-5.6-sol"],
  ["deepseek", "deepseek-flash"],
  ["opencode-go", "deepseek-v4-flash"],
  ["opencode-go", "deepseek-v4-pro"],
  ["opencode-go", "deepseek-v4-flash-vision-exp"],
  ["opencode-go", "kimi-k2.6"],
  ["opencode-go", "qwen3.8-flash"],
  ["opencode-go", "minimax-m3"],
  ["ollama-cloud", "deepseek-v4.1-flash"],
  ["ollama-cloud", "deepseek-v4-pro:0813"],
  ["ollama-cloud", "minimax-m3"],
  ["google", "gemini-3.1-pro-preview"],
  ["anthropic", "claude-x"],
  ["github-copilot", "gpt-5-copilot"],
];

const result = bench("output-shaper-model-gating", () => {
  for (const [providerID, modelID] of PROVIDER_MODEL_MATRIX) {
    isTargetModel(providerID, modelID);
    getClampOptions(providerID, "low");
  }
});

process.stdout.write(`${JSON.stringify(result)}\n`);
