// configs/opencode/aspect-dynamics/logging.mjs
// Logging helpers for aspect-dynamics plugin

const PLUGIN_PREFIX = "[aspect-dynamics]";

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
