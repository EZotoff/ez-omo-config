// configs/opencode/aspect-dynamics/config.mjs
// Stub config loader for aspect-dynamics plugin

const DEFAULT_CONFIG = {
  enabled: true,
  logLevel: "info",
  heuristicPreFilter: false,
  contextWindowTurns: 10,
  // Deferred fields — accepted but inert in MVP (zero network calls)
  scoringModel: null,
  polishingModel: null,
  dreamAgent: null,
};

// Test override — set by harness to inject custom config values
// Uses a mutable object so ESM importers can reassign the .value property
export const __testConfigOverride = { value: null };

export async function loadConfig() {
  const config = __testConfigOverride.value
    ? { ...DEFAULT_CONFIG, ...__testConfigOverride.value }
    : { ...DEFAULT_CONFIG };

  // Validate config
  if (__testConfigOverride.value && __testConfigOverride.value.activeSets !== undefined && !Array.isArray(__testConfigOverride.value.activeSets)) {
    console.warn(`[aspect-dynamics] Invalid config: activeSets must be an array, got ${typeof __testConfigOverride.value.activeSets}`);
    return { ...DEFAULT_CONFIG, enabled: false };
  }

  // Log deferred-field presence at startup (informational only, no network calls)
  const deferred = [];
  if (config.scoringModel) deferred.push("scoringModel");
  if (config.polishingModel) deferred.push("polishingModel");
  if (config.dreamAgent) deferred.push("dreamAgent");
  if (deferred.length > 0) {
    console.info(`[aspect-dynamics] Deferred fields present (inert in MVP): ${deferred.join(", ")}`);
  }

  return config;
}

export function mergeConfig(base, override) {
  return { ...base, ...override };
}
