// configs/opencode/skill-nudger/logging.mjs
// Structured proof-event logging for skill-nudger plugin

import { appendFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

const PLUGIN_PREFIX = "[skill-nudger]";
const LOG_LEVELS = { silent: 4, error: 3, warn: 2, info: 1 };
let currentLogLevel = "warn";

const MAX_PROOF_EVENTS = 1000;
const PROOF_DIR = join(homedir(), ".local", "share", "opencode", "skill-nudger");
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
  const record = { ts, system: "skill-nudger", event: eventType, status, ...payload };

  if (__testProofOverride.value) {
    __testProofOverride.value.push(record);
    if (__testProofOverride.value.length > MAX_PROOF_EVENTS) {
      __testProofOverride.value.splice(0, __testProofOverride.value.length - MAX_PROOF_EVENTS);
    }
    return;
  }

  if (!ensureProofDir()) {
    return;
  }

  try {
    appendFileSync(PROOF_PATH, `${JSON.stringify(record)}\n`, "utf8");
    truncateProofIfNeeded();
  } catch (err) {
    console.error(`${PLUGIN_PREFIX} proof write failed: ${err.message}`);
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
    console.error(`${PLUGIN_PREFIX} proof truncation failed: ${err.message}`);
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
