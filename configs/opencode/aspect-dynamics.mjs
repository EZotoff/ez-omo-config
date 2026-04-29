// configs/opencode/aspect-dynamics.mjs
// Aspect Dynamics config-layer plugin surface

import { loadConfig } from "./aspect-dynamics/config.mjs";
import { extractContext, getEventSessionID, hasRecursionGuard, prefilterContext } from "./aspect-dynamics/context.mjs";
import { rankAspects, scoreAspects, shouldNudge } from "./aspect-dynamics/heuristics.mjs";
import { logEvent, logInfo, logWarn } from "./aspect-dynamics/logging.mjs";
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
  const sets = await loadSets();

  logInfo("Plugin loaded");

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
            logWarn(`Child session ${sessionID} ignored — no aspect-dynamics tracking`);
            return;
          }
          getSessionState(sessionID);
          break;
        }

        case "session.deleted": {
          logEvent("session.deleted", sessionID);
          deleteSessionState(sessionID);
          break;
        }

        case "session.idle": {
          logEvent("session.idle", sessionID);

          if (!canProcess(sessionID)) {
            const state = getSessionState(sessionID);
            if (state.circuitBroken) {
              logWarn(`Session ${sessionID} skipped — circuit breaker open`);
            } else if (state.inFlight) {
              logWarn(`Session ${sessionID} skipped — action already in flight`);
            }
            return;
          }

          markInFlight(sessionID, true);

          try {
            const context = await extractContext(ctx, sessionID, config);
            if (!context) {
              logWarn(`No context for session ${sessionID}`);
              recordFailure(sessionID);
              return;
            }

            if (hasRecursionGuard(context)) {
              logWarn(`Session ${sessionID} skipped — recursion guard detected aspect-dynamics nudge`);
              recordSuccess(sessionID);
              return;
            }

            // Prefilter: skip scoring if no heuristic phrases match
            if (!prefilterContext(context, sets, config)) {
              logEvent("session.idle", sessionID, "prefilter=skip");
              recordSuccess(sessionID);
              return;
            }

            // Deduplication: skip if already handled this assistant message
            const latestAssistantId = context.latestAssistantMessageId;
            const lastHandled = getLastHandledAssistantMessageId(sessionID);
            if (latestAssistantId && latestAssistantId === lastHandled) {
              logWarn(`Session ${sessionID} skipped — already handled assistant message ${latestAssistantId}`);
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
                }
              }
            }

            const state = getSessionState(sessionID);
            state.scores = new Map(scoring.allScores);

            updateSessionState(sessionID, { aspects: ranked });

            // Mark success and update dedup tracker
            recordSuccess(sessionID);
            if (latestAssistantId && !ctx?.client?.session?.promptAsync) {
              setLastHandledAssistantMessageId(sessionID, latestAssistantId);
            }
          } catch (err) {
            logWarn(`Error processing session.idle for ${sessionID}: ${err.message}`);
            recordFailure(sessionID);
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
