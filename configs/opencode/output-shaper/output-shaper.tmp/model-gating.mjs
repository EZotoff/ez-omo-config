// configs/opencode/output-shaper/model-gating.mjs
// Provider/model gating table for output-shaper plugin

// Per-provider clamp options and their allowed thinking-level values.
//
// IMPORTANT — `field` must be the OpenCode providerOptions key (the AI SDK
// option name), NOT the raw HTTP body parameter name. The chat.params hook
// writes into output.options, which flows to streamText providerOptions
// (packages/opencode/src/session/llm.ts) and from there into the SDK model:
//
//   - @ai-sdk/openai-compatible (zai-coding-plan, kimi-for-coding-oauth,
//     deepseek, opencode-go, ollama-cloud, …): the Zod schema accepts ONLY
//     `reasoningEffort` (camelCase) and maps it to body `reasoning_effort`
//     (dist/index.mjs: openaiCompatibleLanguageModelChatOptions + body
//     builder). A snake_case `reasoning_effort` option is silently dropped
//     and never reaches the provider — that was the 2026-08/09 silent no-op
//     bug (zero measured reduction for zai/opencode-go on resume turns).
//   - @ai-sdk/google: effort lives under `thinkingConfig.thinkingLevel`
//     (Zod: thinkingConfig { thinkingLevel: enum(minimal,low,medium,high) });
//     a top-level `thinkingLevel` string is dropped the same way.
//   - @ai-sdk/openai: `reasoningEffort` directly.
//   - kimi-for-coding (K2.7 id): the opencode-kimi-full plugin reads
//     `options.reasoning_effort ?? options.reasoningEffort` (both casings)
//     and rewrites it into the body, so camelCase works there too. The `k3`
//     id gets no plugin body-shaping and relies on this table like every
//     other openai-compatible model.
//
// Verified against live endpoints 2026-09-15 (/tmp/opencode/ab_test_reasoning.py,
// resume-style prompt, reasoning tokens via usage.completion_tokens_details):
//   - zai coding-plan glm-5.3 / glm-5.3-flash: body reasoning_effort:"low"
//     cuts reasoning from ~106–172 tok to 0 and ~halves latency.
//   - ollama.com/v1 deepseek-v4-pro:0813: reasoning_effort:"low" ≈ halves
//     reasoning chars; "none" disables thinking entirely.
//   - ollama.com/v1 minimax-m3: reasoning_effort:"low" INCREASED reasoning
//     erratically (177→982 chars in one run) → ollama-cloud is gated to a
//     DeepSeek-only model allowlist.
//
// Optional `models` array: when present, only these model ids are clamped
// for the provider (empty/absent = all models of the provider).
const CLAMP_TABLE = {
  "zai-coding-plan":       { field: "reasoningEffort", values: { low: "low", medium: "medium", high: "high", max: "max" } },
  "kimi-for-coding-oauth": { field: "reasoningEffort", values: { low: "low", medium: "medium", high: "high", max: "max" } },
  "openai":                { field: "reasoningEffort", values: { low: "low", medium: "medium", high: "high", xhigh: "xhigh", max: "max" } },
  "deepseek":              { field: "reasoningEffort", values: { low: "low", medium: "medium", high: "high", max: "max" } },
  "opencode-go": {
    field: "reasoningEffort",
    values: { low: "low", medium: "medium", high: "high", max: "max" },
    // minimax-m3 excluded: the model reacts erratically/adversely to
    // reasoning_effort (verified on ollama.com's gateway 2026-09-15; the
    // exclusion follows the model, not the gateway). Allowlist keeps future
    // opencode-go models fail-closed until verified.
    models: ["deepseek-v4-flash", "deepseek-v4-pro", "deepseek-v4-flash-vision-exp", "kimi-k2.6", "qwen3.8-flash"],
  },
  "ollama-cloud": {
    field: "reasoningEffort",
    values: { low: "low", medium: "medium", high: "high", max: "max" },
    models: ["deepseek-v4.1-flash", "deepseek-v4-pro:0813"],
  },
  "google": {
    field: "thinkingConfig",
    values: {
      minimal: { thinkingLevel: "minimal" },
      low: { thinkingLevel: "low" },
      medium: { thinkingLevel: "medium" },
      high: { thinkingLevel: "high" },
    },
  },
};


const EXCLUDED_PROVIDERS = new Set(["anthropic", "github-copilot"]);

// Returns true when the provider is clampable (in CLAMP_TABLE, not excluded)
// and — when the entry carries a model allowlist — the model id is listed.
export function isTargetModel(providerID, modelID) {
  const entry = CLAMP_TABLE[providerID];
  if (!entry || EXCLUDED_PROVIDERS.has(providerID)) return false;
  if (Array.isArray(entry.models) && modelID !== undefined) {
    return entry.models.includes(modelID);
  }
  return true;
}

// Returns { field, value } for the given provider + level, or null when
// the provider is not clampable or the level is not defined for it.
export function getClampOptions(providerID, level) {
  const entry = CLAMP_TABLE[providerID];
  if (!entry) return null;
  const value = entry.values[level];
  if (value === undefined) return null;
  return { field: entry.field, value };
}
