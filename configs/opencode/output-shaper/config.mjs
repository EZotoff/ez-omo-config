// configs/opencode/output-shaper/config.mjs
// Config loader for output-shaper plugin

import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

const DEFAULT_CONFIG = {
  enabled: true,
  logLevel: "info",
  tersenessInstruction:
    "Be terse: no preambles, no restated code, minimal reasoning on routine ops. Deep thinking only for complex problems and errors.",
  resumeThinkingLevel: "low",
};

const LOG_LEVELS = { silent: 4, error: 3, warn: 2, info: 1 };

const OMO_CONFIG_PATH = join(homedir(), ".config", "opencode", "oh-my-openagent.json");

// Test override — set by harness to inject custom config values
// Uses a mutable object so ESM importers can reassign the .value property
export const __testConfigOverride = { value: null };

export function setTestConfig(override) {
  __testConfigOverride.value = override;
}

export function clearTestConfig() {
  __testConfigOverride.value = null;
}

function validateConfig(candidate) {
  if (!candidate || typeof candidate !== "object" || Array.isArray(candidate)) {
    console.warn("[output-shaper] Invalid config: outputShaper must be an object");
    return false;
  }

  if (candidate.enabled !== undefined && typeof candidate.enabled !== "boolean") {
    console.warn(`[output-shaper] Invalid config: enabled must be boolean, got ${typeof candidate.enabled}`);
    return false;
  }

  if (candidate.logLevel !== undefined && !(candidate.logLevel in LOG_LEVELS)) {
    console.warn(
      `[output-shaper] Invalid config: logLevel must be one of ${Object.keys(LOG_LEVELS).join(", ")}, got ${candidate.logLevel}`
    );
    return false;
  }

  if (candidate.tersenessInstruction !== undefined && typeof candidate.tersenessInstruction !== "string") {
    console.warn(
      `[output-shaper] Invalid config: tersenessInstruction must be a string, got ${typeof candidate.tersenessInstruction}`
    );
    return false;
  }

  if (candidate.resumeThinkingLevel !== undefined && typeof candidate.resumeThinkingLevel !== "string") {
    console.warn(
      `[output-shaper] Invalid config: resumeThinkingLevel must be a string, got ${typeof candidate.resumeThinkingLevel}`
    );
    return false;
  }

  return true;
}

export async function loadConfig() {
  if (__testConfigOverride.value) {
    if (!validateConfig(__testConfigOverride.value)) {
      return { ...DEFAULT_CONFIG, enabled: false };
    }

    return { ...DEFAULT_CONFIG, ...__testConfigOverride.value };
  }

  let raw;
  try {
    raw = readFileSync(OMO_CONFIG_PATH, "utf8");
  } catch (err) {
    console.warn(`[output-shaper] outputShaper config not found at ${OMO_CONFIG_PATH}: ${err.message}`);
    return null;
  }

  let parsed;
  try {
    parsed = JSON.parse(raw);
  } catch (err) {
    console.warn(`[output-shaper] Failed to parse ${OMO_CONFIG_PATH}: ${err.message}`);
    return null;
  }

  const outputShaper = parsed?.outputShaper;
  if (!outputShaper || typeof outputShaper !== "object" || Array.isArray(outputShaper)) {
    console.warn(`[output-shaper] Missing outputShaper block in ${OMO_CONFIG_PATH}`);
    return null;
  }

  if (!validateConfig(outputShaper)) {
    return { ...DEFAULT_CONFIG, enabled: false };
  }

  return { ...DEFAULT_CONFIG, ...outputShaper };
}
