// configs/opencode/aspect-dynamics/config.mjs
// Stub config loader for aspect-dynamics plugin

const DEFAULT_CONFIG = {
  enabled: true,
  logLevel: "info",
  nudgeThreshold: 0.7,
  maxAspectsPerSession: 8,
};

export async function loadConfig() {
  return { ...DEFAULT_CONFIG };
}

export function mergeConfig(base, override) {
  return { ...base, ...override };
}
