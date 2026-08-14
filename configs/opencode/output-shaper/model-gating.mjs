// configs/opencode/output-shaper/model-gating.mjs
// Provider/model gating table for output-shaper plugin

// Per-provider clamp field names and their allowed thinking-level values.
// The active thinking level is mapped to a provider-specific request option
// (e.g. zai "thinking_budget", openai "reasoningEffort", google "thinkingLevel").
// GLM-5.3 dropped thinking_budget for reasoning_effort (low/high/max only).
const CLAMP_TABLE = {
  "zai-coding-plan":       { field: "reasoning_effort", values: { low: "low", high: "high", max: "max" } },
  "kimi-for-coding-oauth": { field: "reasoning_effort", values: { low: "low", medium: "medium", high: "high" } },
  "openai":                { field: "reasoningEffort",   values: { low: "low", medium: "medium", high: "high", xhigh: "xhigh", max: "max" } },
  "google":                { field: "thinkingLevel",     values: { minimal: "minimal", low: "low", medium: "medium", high: "high" } },
  "deepseek":              { field: "reasoning_effort",  values: { low: "low", medium: "medium", high: "high", max: "max" } },
  "opencode-go":           { field: "reasoning_effort",  values: { low: "low", medium: "medium", high: "high", max: "max" } },
};


const EXCLUDED_PROVIDERS = new Set(["anthropic", "github-copilot"]);

// Returns true when the provider is clampable (in CLAMP_TABLE) and not excluded.
export function isTargetModel(providerID) {
  return providerID in CLAMP_TABLE && !EXCLUDED_PROVIDERS.has(providerID);
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
