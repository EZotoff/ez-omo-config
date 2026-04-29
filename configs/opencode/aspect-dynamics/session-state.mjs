// configs/opencode/aspect-dynamics/session-state.mjs
// Stub session state module for aspect-dynamics plugin

const stateBySession = new Map();

export function getSessionState(sessionID) {
  if (!stateBySession.has(sessionID)) {
    stateBySession.set(sessionID, {
      aspects: [],
      scores: new Map(),
      nudgesSent: 0,
      createdAt: Date.now(),
    });
  }
  return stateBySession.get(sessionID);
}

export function updateSessionState(sessionID, patch) {
  const existing = getSessionState(sessionID);
  stateBySession.set(sessionID, { ...existing, ...patch });
}

export function deleteSessionState(sessionID) {
  stateBySession.delete(sessionID);
}

export function listActiveSessions() {
  return Array.from(stateBySession.keys());
}
