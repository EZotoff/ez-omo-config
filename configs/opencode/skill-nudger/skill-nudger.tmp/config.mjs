// configs/opencode/skill-nudger/config.mjs
// Config loader for skill-nudger plugin — reads `skillNudger` from oh-my-openagent.json

import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { logWarn } from "./logging.mjs";

const DEFAULT_CONFIG = {
  enabled: true,
  logLevel: "warn",
  windowSize: 15,
  repeatFailureThreshold: 2,
  loopThreshold: 8,
  maxNudgesPerSession: 2,
  cooldownToolCalls: 10,
  freshnessMs: 90_000,
  disabledSignals: [],
};

const LOG_LEVELS = { silent: 4, error: 3, warn: 2, info: 1 };

const OMO_CONFIG_PATH = join(homedir(), ".config", "opencode", "oh-my-openagent.json");

// Test override — set by harness to inject custom config values
export const __testConfigOverride = { value: null };

function validateConfig(candidate) {
  if (!candidate || typeof candidate !== "object" || Array.isArray(candidate)) {
    logWarn("Invalid config: skillNudger must be an object");
    return false;
  }

  if (candidate.enabled !== undefined && typeof candidate.enabled !== "boolean") {
    logWarn(`Invalid config: enabled must be boolean, got ${typeof candidate.enabled}`);
    return false;
  }

  for (const key of ["windowSize", "repeatFailureThreshold", "loopThreshold", "maxNudgesPerSession", "cooldownToolCalls", "freshnessMs"]) {
    if (candidate[key] !== undefined && (!Number.isFinite(candidate[key]) || candidate[key] <= 0)) {
      logWarn(`Invalid config: ${key} must be a positive number`);
      return false;
    }
  }

  if (candidate.disabledSignals !== undefined && !Array.isArray(candidate.disabledSignals)) {
    logWarn(`Invalid config: disabledSignals must be an array, got ${typeof candidate.disabledSignals}`);
    return false;
  }

  if (candidate.logLevel !== undefined && !(candidate.logLevel in LOG_LEVELS)) {
    logWarn(`Invalid config: logLevel must be one of ${Object.keys(LOG_LEVELS).join(", ")}`);
    return false;
  }

  return true;
}

export async function loadConfig() {
  if (__testConfigOverride.value) {
    return { ...DEFAULT_CONFIG, ...__testConfigOverride.value };
  }

  try {
    const raw = JSON.parse(readFileSync(OMO_CONFIG_PATH, "utf8"));
    const candidate = raw?.skillNudger;
    if (candidate === undefined) {
      return { ...DEFAULT_CONFIG };
    }
    if (!validateConfig(candidate)) {
      return null;
    }
    return { ...DEFAULT_CONFIG, ...candidate };
  } catch (err) {
    if (err.code === "ENOENT") {
      return { ...DEFAULT_CONFIG };
    }
    logWarn(`Failed to read config: ${err.message}`);
    return null;
  }
}
