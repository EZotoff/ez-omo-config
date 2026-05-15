// configs/opencode/aspect-dynamics/logging.mjs
// Logging helpers for aspect-dynamics plugin

import { appendFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";

const PLUGIN_PREFIX = "[aspect-dynamics]";
const MAX_PROOF_EVENTS = 1000;
const DEFAULT_PROOF_PATH = join(homedir(), ".local", "share", "opencode", "aspect-dynamics", "events.jsonl");

let proofSink = {
  path: null,
  enabled: false,
  lineCount: 0,
};

export function logInfo(msg) {
  console.info(`${PLUGIN_PREFIX} ${msg}`);
}

export function logWarn(msg) {
  console.warn(`${PLUGIN_PREFIX} ${msg}`);
}

export function logError(msg) {
  console.error(`${PLUGIN_PREFIX} ${msg}`);
}

export function logEvent(eventType, sessionID, extra = "") {
  const ts = new Date().toISOString();
  const line = `[${ts}] ${PLUGIN_PREFIX} [${eventType}] session=${sessionID} ${extra}`.trim();
  console.info(line);
}

// ── Proof Event Sink ─────────────────────────────────────────────

export function initProofSink(config = {}) {
  const proofPath = config.proofPath || DEFAULT_PROOF_PATH;
  proofSink.path = proofPath;
  proofSink.enabled = config.proofEnabled !== false;

  if (!proofSink.enabled) return;

  try {
    const dir = dirname(proofPath);
    if (!existsSync(dir)) {
      mkdirSync(dir, { recursive: true });
    }

    if (existsSync(proofPath)) {
      const content = readFileSync(proofPath, "utf8");
      proofSink.lineCount = content.split("\n").filter((line) => line.trim().length > 0).length;
    } else {
      proofSink.lineCount = 0;
    }
  } catch (err) {
    logWarn(`Failed to initialize proof sink: ${err.message}`);
    proofSink.enabled = false;
  }
}

export function closeProofSink() {
  proofSink = { path: null, enabled: false, lineCount: 0 };
}

export function emitProofEvent(eventType, data = {}) {
  if (!proofSink.enabled || !proofSink.path) return;

  const event = {
    ts: new Date().toISOString(),
    system: "aspect-dynamics",
    event: eventType,
    ...data,
  };

  try {
    const line = JSON.stringify(event) + "\n";
    appendFileSync(proofSink.path, line);
    proofSink.lineCount++;

    if (proofSink.lineCount > MAX_PROOF_EVENTS) {
      enforceRetention(MAX_PROOF_EVENTS);
    }
  } catch (err) {
    logWarn(`Failed to emit proof event: ${err.message}`);
  }
}

export function enforceRetention(maxLines = MAX_PROOF_EVENTS) {
  if (!proofSink.enabled || !proofSink.path) return;

  try {
    const content = readFileSync(proofSink.path, "utf8");
    const lines = content.split("\n").filter((line) => line.trim().length > 0);

    if (lines.length > maxLines) {
      const kept = lines.slice(-maxLines);
      writeFileSync(proofSink.path, kept.join("\n") + "\n");
      proofSink.lineCount = kept.length;
    }
  } catch (err) {
    logWarn(`Failed to enforce proof retention: ${err.message}`);
  }
}
