// configs/opencode/output-shaper/logging.mjs
// File-based logging helpers for output-shaper plugin

import { appendFileSync, existsSync, mkdirSync, renameSync, statSync, unlinkSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

const PLUGIN_PREFIX = "[output-shaper]";
const LOG_LEVELS = { silent: 4, error: 3, warn: 2, info: 1 };
let currentLogLevel = "info";

const LOG_DIR = join(homedir(), ".config", "opencode");
const LOG_PATH = join(LOG_DIR, "output-shaper.log");
const LOG_MAX_BYTES = 2 * 1024 * 1024;

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

// Size-based rotation mirroring provider-connect-retry.mjs:21-32. Fail-open:
// a missing log file or a failed rename must never break the plugin.
function rotateLogIfNeeded() {
  try {
    const stat = statSync(LOG_PATH);
    if (stat.size > LOG_MAX_BYTES) {
      const backup = `${LOG_PATH}.1`;
      try { unlinkSync(backup); } catch {}
      try { renameSync(LOG_PATH, backup); } catch { /* failed rotation must never delete diagnostic evidence — the log keeps growing until the next attempt */ }
    }
  } catch {
    // file doesn't exist yet — nothing to rotate
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
    rotateLogIfNeeded();
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

// Fail-open timing instrumentation. nowMs() is a monotonic millisecond clock;
// logTiming() emits at info level so existing level filtering still applies.
export function nowMs() {
  return Number(process.hrtime.bigint()) / 1e6;
}

export function logTiming(hook, startedAt, extra = "") {
  try {
    write("info", `hook=${hook} dur_ms=${(nowMs() - startedAt).toFixed(2)} ${extra}`.trim());
  } catch {
    // Timing instrumentation must never break the plugin
  }
}
