// configs/opencode/aspect-dynamics/session-state.mjs
// In-memory session state tracking for aspect-dynamics plugin

const stateBySession = new Map();

export function getSessionState(sessionID) {
  if (!stateBySession.has(sessionID)) {
    stateBySession.set(sessionID, {
      isRoot: true,
      inFlight: false,
      lastHandledAssistantMessageId: null,
      failureCount: 0,
      circuitBroken: false,
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

export async function isChildSession(ctx, sessionID) {
  if (!ctx?.client?.session?.get) {
    return false;
  }
  try {
    const response = await ctx.client.session.get({ path: { id: sessionID } });
    const parentID = response?.data?.parentID ?? null;
    return parentID !== null;
  } catch {
    return false;
  }
}

export function markInFlight(sessionID, bool) {
  updateSessionState(sessionID, { inFlight: bool });
}

export function recordFailure(sessionID) {
  const state = getSessionState(sessionID);
  const newFailureCount = Math.min(state.failureCount + 1, 3);
  const patch = { failureCount: newFailureCount };
  if (newFailureCount >= 3) {
    patch.circuitBroken = true;
  }
  updateSessionState(sessionID, patch);
}

export function recordSuccess(sessionID) {
  updateSessionState(sessionID, { failureCount: 0, circuitBroken: false });
}

export function canProcess(sessionID) {
  const state = getSessionState(sessionID);
  return !state.inFlight && !state.circuitBroken;
}

export function getLastHandledAssistantMessageId(sessionID) {
  const state = getSessionState(sessionID);
  return state.lastHandledAssistantMessageId;
}

export function setLastHandledAssistantMessageId(sessionID, id) {
  updateSessionState(sessionID, { lastHandledAssistantMessageId: id });
}

export function listActiveSessions() {
  return Array.from(stateBySession.keys());
}
