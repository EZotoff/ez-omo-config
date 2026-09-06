// configs/opencode/output-shaper/logging.mjs
// File-based logging helpers for output-shaper plugin

import { appendFileSync, existsSync, mkdirSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

const PLUGIN_PREFIX = "[output-shaper]";
const LOG_LEVELS = { silent: 4, error: 3, warn: 2, info: 1 };
let currentLogLevel = "info";

const LOG_DIR = join(homedir(), ".config", "opencode");
const LOG_PATH = join(LOG_DIR, "output-shaper.log");

// Test override — allows harness to intercept diagnostic logs without file I/O
export const __testLogOverride = { value: null };

export function setLogLevel(level) {
  currentLogLevel = level in LOG_LEVELS ? level : "warn";
}

function shouldLog(level) {
  return LOG_LEVELS[level] >= LOG_LEVELS[currentLogLevel];
}

function ensureLogDir() {
  try {
    if (!existsSync(LOG_DIR)) {
      mkdirSync(LOG_DIR, { recursive: true });
    }
    return true;
  } catch {
    return false;
  }
}

function write(level, msg) {
  if (!shouldLog(level)) return;
  const line = `[${new Date().toISOString()}] ${PLUGIN_PREFIX} [${level}] ${msg}`;
  if (__testLogOverride.value) {
    __testLogOverride.value.push({ level, msg: line });
    return;
  }
  if (!ensureLogDir()) return;

  try {
    appendFileSync(LOG_PATH, `${line}\n`, "utf8");
  } catch {
    // File write failures are silently dropped — logging must never break the plugin
  }
}

export function logInfo(msg) {
  write("info", msg);
}

export function logWarn(msg) {
  write("warn", msg);
}

export function logError(msg) {
  write("error", msg);
}
