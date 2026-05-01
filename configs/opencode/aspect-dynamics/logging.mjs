// configs/opencode/aspect-dynamics/logging.mjs
// Logging helpers for aspect-dynamics plugin

import { appendFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

const PLUGIN_PREFIX = "[aspect-dynamics]";
const LOG_LEVELS = { silent: 4, error: 3, warn: 2, info: 1 };
let currentLogLevel = "warn";

const MAX_PROOF_EVENTS = 1000;
const PROOF_DIR = join(homedir(), ".local", "share", "opencode", "aspect-dynamics");
const PROOF_PATH = join(PROOF_DIR, "events.jsonl");

// Test override — allows harness to intercept proof events without file I/O
export const __testProofOverride = { value: null };

export function setLogLevel(level) {
  currentLogLevel = level in LOG_LEVELS ? level : "warn";
}

function shouldLog(level) {
  return LOG_LEVELS[level] >= LOG_LEVELS[currentLogLevel];
}

function ensureProofDir() {
  try {
    if (!existsSync(PROOF_DIR)) {
      mkdirSync(PROOF_DIR, { recursive: true });
    }
    return true;
  } catch {
    return false;
  }
}

export function emitProof(eventType, payload = {}) {
  const ts = new Date().toISOString();
  const status = eventType === "failure" || eventType === "circuit_open" ? "failure" : "success";
  const record = { ts, system: "aspect-dynamics", event: eventType, status, ...payload };

  if (__testProofOverride.value) {
    __testProofOverride.value.push(record);
    // Enforce retention cap even in test override mode
    if (__testProofOverride.value.length > MAX_PROOF_EVENTS) {
      __testProofOverride.value.splice(0, __testProofOverride.value.length - MAX_PROOF_EVENTS);
    }
    return;
  }

  if (!ensureProofDir()) {
    return;
  }

  try {
    const line = `${JSON.stringify(record)}\n`;
    appendFileSync(PROOF_PATH, line, "utf8");

    // Retention cap: truncate to most recent MAX_PROOF_EVENTS lines
    truncateProofIfNeeded();
  } catch (err) {
    console.error("[aspect-dynamics proof] write failed:", err);
  }
}

function truncateProofIfNeeded() {
  try {
    if (!existsSync(PROOF_PATH)) return;
    const content = readFileSync(PROOF_PATH, "utf8");
    const lines = content.split("\n").filter((l) => l.trim() !== "");
    if (lines.length > MAX_PROOF_EVENTS) {
      const kept = lines.slice(-MAX_PROOF_EVENTS);
      writeFileSync(PROOF_PATH, `${kept.join("\n")}\n`, "utf8");
    }
  } catch (err) {
    console.error("[aspect-dynamics proof] truncation failed:", err);
  }
}

export function readProofEvents() {
  if (__testProofOverride.value) {
    return [...__testProofOverride.value];
  }

  try {
    if (!existsSync(PROOF_PATH)) return [];
    const content = readFileSync(PROOF_PATH, "utf8");
    return content
      .split("\n")
      .filter((l) => l.trim() !== "")
      .map((l) => JSON.parse(l));
  } catch {
    return [];
  }
}

export function resetProofEvents() {
  if (__testProofOverride.value) {
    __testProofOverride.value.length = 0;
    return;
  }

  try {
    if (existsSync(PROOF_PATH)) {
      writeFileSync(PROOF_PATH, "", "utf8");
    }
  } catch (err) {
    console.error("[aspect-dynamics proof] reset failed:", err);
  }
}

export function logInfo(msg) {
  if (!shouldLog("info")) return;
  console.info(`${PLUGIN_PREFIX} ${msg}`);
}

export function logWarn(msg) {
  if (!shouldLog("warn")) return;
  console.warn(`${PLUGIN_PREFIX} ${msg}`);
}

export function logError(msg) {
  if (!shouldLog("error")) return;
  console.error(`${PLUGIN_PREFIX} ${msg}`);
}

export function logEvent(eventType, sessionID, extra = "") {
  if (!shouldLog("info")) return;
  const ts = new Date().toISOString();
  const line = `[${ts}] ${PLUGIN_PREFIX} [${eventType}] session=${sessionID} ${extra}`.trim();
  console.info(line);
}
