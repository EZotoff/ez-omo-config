// configs/opencode/aspect-dynamics/config.mjs
// Stub config loader for aspect-dynamics plugin

import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

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

const OMO_CONFIG_PATH = join(homedir(), ".config", "opencode", "oh-my-openagent.json");

// Test override — set by harness to inject custom config values
// Uses a mutable object so ESM importers can reassign the .value property
export const __testConfigOverride = { value: null };

function validateConfig(candidate) {
  if (!candidate || typeof candidate !== "object" || Array.isArray(candidate)) {
    console.warn("[aspect-dynamics] Invalid config: aspectDynamics must be an object");
    return false;
  }

  if (candidate.activeSets !== undefined && !Array.isArray(candidate.activeSets)) {
    console.warn(`[aspect-dynamics] Invalid config: activeSets must be an array, got ${typeof candidate.activeSets}`);
    return false;
  }

  if (candidate.heuristicPreFilter !== undefined && typeof candidate.heuristicPreFilter !== "boolean") {
    console.warn(
      `[aspect-dynamics] Invalid config: heuristicPreFilter must be boolean, got ${typeof candidate.heuristicPreFilter}`
    );
    return false;
  }

  if (
    candidate.contextWindowTurns !== undefined
    && (!Number.isFinite(candidate.contextWindowTurns) || candidate.contextWindowTurns <= 0)
  ) {
    console.warn(
      `[aspect-dynamics] Invalid config: contextWindowTurns must be a positive number, got ${candidate.contextWindowTurns}`
    );
    return false;
  }

  return true;
}

function logDeferredFields(config) {
  const deferred = [];
  if (config.scoringModel) deferred.push("scoringModel");
  if (config.polishingModel) deferred.push("polishingModel");
  if (config.dreamAgent) deferred.push("dreamAgent");
  if (deferred.length > 0) {
    console.info(`[aspect-dynamics] Deferred fields present (inert in MVP): ${deferred.join(", ")}`);
  }
}

export async function loadConfig() {
  if (__testConfigOverride.value) {
    if (!validateConfig(__testConfigOverride.value)) {
      return { ...DEFAULT_CONFIG, enabled: false };
    }

    const testConfig = { ...DEFAULT_CONFIG, ...__testConfigOverride.value };
    logDeferredFields(testConfig);
    return testConfig;
  }

  let raw;
  try {
    raw = readFileSync(OMO_CONFIG_PATH, "utf8");
  } catch (err) {
    console.warn(`[aspect-dynamics] aspectDynamics config not found at ${OMO_CONFIG_PATH}: ${err.message}`);
    return null;
  }

  let parsed;
  try {
    parsed = JSON.parse(raw);
  } catch (err) {
    console.warn(`[aspect-dynamics] Failed to parse ${OMO_CONFIG_PATH}: ${err.message}`);
    return null;
  }

  const aspectDynamics = parsed?.aspectDynamics;
  if (!aspectDynamics || typeof aspectDynamics !== "object" || Array.isArray(aspectDynamics)) {
    console.warn(`[aspect-dynamics] Missing aspectDynamics block in ${OMO_CONFIG_PATH}`);
    return null;
  }

  if (!validateConfig(aspectDynamics)) {
    return { ...DEFAULT_CONFIG, enabled: false };
  }

  const config = { ...DEFAULT_CONFIG, ...aspectDynamics };
  logDeferredFields(config);

  return config;
}

export function mergeConfig(base, override) {
  return { ...base, ...override };
}
