// configs/opencode/aspect-dynamics.mjs
// Aspect Dynamics config-layer plugin surface

import { loadConfig } from "./aspect-dynamics/config.mjs";
import { extractContext, getEventSessionID, hasRecursionGuard, prefilterContext } from "./aspect-dynamics/context.mjs";
import { rankAspects, scoreAspects, shouldNudge } from "./aspect-dynamics/heuristics.mjs";
import { emitProof, logEvent, logInfo, logWarn, setLogLevel } from "./aspect-dynamics/logging.mjs";
import { buildNudge } from "./aspect-dynamics/nudge.mjs";
import {
  canProcess,
  deleteSessionState,
  getLastHandledAssistantMessageId,
  getSessionState,
  isChildSession,
  markInFlight,
  recordFailure,
  recordSuccess,
  setLastHandledAssistantMessageId,
  updateSessionState,
} from "./aspect-dynamics/session-state.mjs";
import { loadSets } from "./aspect-dynamics/sets.mjs";

export default async function aspectDynamicsPlugin(ctx) {
  const config = await loadConfig();
  if (!config) {
    logWarn("No aspectDynamics config loaded; plugin running in no-op mode");
    return {
      event: async () => {},
    };
  }

  setLogLevel(config.logLevel);

  const sets = await loadSets();

  logInfo("Plugin loaded");
  emitProof("plugin_loaded", { version: "1.0.0" });

  // Deferred-field safeguard: scoringModel, polishingModel, dreamAgent are
  // accepted from config but deliberately unused in MVP. Zero network calls
  // are made based on these fields. They are reserved for future use.
  // See config.mjs loadConfig() for deferred-field startup logging.
  if (config.scoringModel || config.polishingModel || config.dreamAgent) {
    logInfo("Deferred fields present (scoringModel/polishingModel/dreamAgent) — inert in MVP, zero network calls");
  }

  return {
    event: async ({ event }) => {
      if (config.enabled === false) return;

      const sessionID = getEventSessionID(event);
      if (!sessionID) return;

      switch (event?.type) {
        case "session.created": {
          logEvent("session.created", sessionID);
          const child = await isChildSession(ctx, sessionID);
          if (child) {
            logInfo(`Child session ${sessionID} ignored — no aspect-dynamics tracking`);
            emitProof("child_session_ignored", { session_id: sessionID });
            return;
          }
          getSessionState(sessionID);
          emitProof("session_created", { session_id: sessionID });
          break;
        }

        case "session.deleted": {
          logEvent("session.deleted", sessionID);
          deleteSessionState(sessionID);
          emitProof("session_deleted", { session_id: sessionID });
          break;
        }

        case "session.idle": {
          logEvent("session.idle", sessionID);
          emitProof("idle_seen", { session_id: sessionID });

          const child = await isChildSession(ctx, sessionID);
          if (child) {
            logInfo(`Session ${sessionID} skipped — child session`);
            return;
          }

          if (!canProcess(sessionID)) {
            const state = getSessionState(sessionID);
            if (state.circuitBroken) {
              logInfo(`Session ${sessionID} skipped — circuit breaker open`);
              emitProof("circuit_open", { session_id: sessionID, failure_count: state.failureCount });
            } else if (state.inFlight) {
              logInfo(`Session ${sessionID} skipped — action already in flight`);
            }
            return;
          }

          markInFlight(sessionID, true);

          try {
            const context = await extractContext(ctx, sessionID, config);
            if (!context) {
              logWarn(`No context for session ${sessionID}`);
              recordFailure(sessionID);
              emitProof("failure", { session_id: sessionID, reason: "no_context" });
              return;
            }

            if (hasRecursionGuard(context)) {
              logInfo(`Session ${sessionID} skipped — recursion guard detected aspect-dynamics nudge`);
              recordSuccess(sessionID);
              return;
            }

            // Prefilter: skip scoring if no heuristic phrases match
            if (!prefilterContext(context, sets, config)) {
              logEvent("session.idle", sessionID, "prefilter=skip");
              emitProof("skip", { session_id: sessionID, reason: "prefilter" });
              recordSuccess(sessionID);
              return;
            }

            // Deduplication: skip if already handled this assistant message
            const latestAssistantId = context.latestAssistantMessageId;
            const lastHandled = getLastHandledAssistantMessageId(sessionID);
            if (latestAssistantId && latestAssistantId === lastHandled) {
              logInfo(`Session ${sessionID} skipped — already handled assistant message ${latestAssistantId}`);
              return;
            }

            const scoring = scoreAspects(context, sets);
            const ranked = rankAspects(scoring.allScores);

            if (scoring.topScore >= 0) {
              const topSet = sets.find(s =>
                Array.from(scoring.allScores.values()).some(e =>
                  e.setId === s.id && e.aspectId === scoring.topAspectId?.split(":")[1]
                )
              );
              const threshold = topSet?.defaultThreshold ?? 0.75;

              if (shouldNudge(scoring.topScore, threshold)) {
                const topEntry = scoring.allScores.get(scoring.topAspectId);
                const nudge = buildNudge(ranked, topEntry);
                if (nudge && ctx?.client?.session?.promptAsync) {
                  if (latestAssistantId) {
                    setLastHandledAssistantMessageId(sessionID, latestAssistantId);
                  }
                  await ctx.client.session.promptAsync({
                    path: { id: sessionID },
                    body: nudge,
                  });
                  logEvent("nudge", sessionID, `aspect=${topEntry.aspectId}, score=${scoring.topScore.toFixed(2)}`);
                  emitProof("nudge_sent", { session_id: sessionID, aspect: topEntry.aspectId, score: scoring.topScore });
                }
              }
            }

            const state = getSessionState(sessionID);
            state.scores = new Map(scoring.allScores);

            emitProof("score", { session_id: sessionID, top_aspect: scoring.topAspectId, top_score: scoring.topScore });

            updateSessionState(sessionID, { aspects: ranked });

            // Mark success and update dedup tracker
            recordSuccess(sessionID);
            if (latestAssistantId) {
              setLastHandledAssistantMessageId(sessionID, latestAssistantId);
            }
          } catch (err) {
            logWarn(`Error processing session.idle for ${sessionID}: ${err.message}`);
            recordFailure(sessionID);
            emitProof("failure", { session_id: sessionID, reason: "exception", error: err.message });
          } finally {
            markInFlight(sessionID, false);
          }

          break;
        }

        default:
          break;
      }
    },
  };
}
