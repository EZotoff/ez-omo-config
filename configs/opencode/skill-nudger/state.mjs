// configs/opencode/skill-nudger/state.mjs
// Per-session nudge guardrails: dedup, cooldown, cap, circuit breaker

const stateBySession = new Map();
const MAX_TRACKED_SESSIONS = 200;

function ensureCapacity() {
  if (stateBySession.size <= MAX_TRACKED_SESSIONS) return;
  // Delete oldest entries (insertion order)
  const excess = stateBySession.size - MAX_TRACKED_SESSIONS;
  let i = 0;
  for (const key of stateBySession.keys()) {
    if (i >= excess) break;
    stateBySession.delete(key);
    i++;
  }
}

export function getSessionState(sessionID) {
  if (!stateBySession.has(sessionID)) {
    ensureCapacity();
    stateBySession.set(sessionID, {
      toolCallCount: 0,
      lastNudgeAtToolCount: -Infinity,
      sentRuleIds: new Set(),
      nudgesSent: 0,
      failureCount: 0,
      circuitBroken: false,
      createdAt: Date.now(),
    });
  }
  return stateBySession.get(sessionID);
}

/**
 * Decide whether a nudge for `ruleId` may be dispatched for this session.
 * Returns { ok: true } or { ok: false, reason }.
 */
export function canNudge(sessionID, ruleId, config, totalCalls) {
  const state = getSessionState(sessionID);
  if (state.circuitBroken) return { ok: false, reason: "circuit_open" };
  if (state.nudgesSent >= config.maxNudgesPerSession) return { ok: false, reason: "cap_reached" };
  if (state.sentRuleIds.has(ruleId)) return { ok: false, reason: "rule_already_sent" };
  if (totalCalls - state.lastNudgeAtToolCount < config.cooldownToolCalls) {
    return { ok: false, reason: "cooldown" };
  }
  return { ok: true };
}

export function recordNudge(sessionID, ruleId, totalCalls) {
  const state = getSessionState(sessionID);
  state.sentRuleIds.add(ruleId);
  state.nudgesSent += 1;
  state.lastNudgeAtToolCount = totalCalls;
}

export function recordFailure(sessionID) {
  const state = getSessionState(sessionID);
  state.failureCount = Math.min(state.failureCount + 1, 3);
  if (state.failureCount >= 3) state.circuitBroken = true;
}

export function recordSuccess(sessionID) {
  const state = getSessionState(sessionID);
  state.failureCount = 0;
  state.circuitBroken = false;
}

export function deleteSessionState(sessionID) {
  stateBySession.delete(sessionID);
}

export function __resetAllState() {
  stateBySession.clear();
}
