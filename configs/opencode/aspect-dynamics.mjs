// configs/opencode/aspect-dynamics.mjs
// Aspect Dynamics config-layer plugin surface

import { loadConfig } from "./aspect-dynamics/config.mjs";
import { loadSets } from "./aspect-dynamics/sets.mjs";
import {
  getSessionState,
  updateSessionState,
  deleteSessionState,
  isChildSession,
  markInFlight,
  recordFailure,
  recordSuccess,
  canProcess,
  setLastHandledAssistantMessageId,
  getLastHandledAssistantMessageId,
} from "./aspect-dynamics/session-state.mjs";
import { extractContext, prefilterContext, getEventSessionID } from "./aspect-dynamics/context.mjs";
import { scoreAspect, shouldNudge, rankAspects } from "./aspect-dynamics/heuristics.mjs";
import { buildNudge, formatNudgeForDispatch } from "./aspect-dynamics/nudge.mjs";
import { logInfo, logWarn, logEvent } from "./aspect-dynamics/logging.mjs";

export default async function aspectDynamicsPlugin(ctx) {
  const config = await loadConfig();
  const sets = await loadSets();

  logInfo("Plugin loaded");

  return {
    event: async ({ event }) => {
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
            logWarn(`Session ${sessionID} skipped — inFlight or circuitBroken`);
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

            const state = getSessionState(sessionID);

            for (const set of sets) {
              for (const aspect of set.aspects) {
                const score = scoreAspect(aspect, context);
                state.scores.set(aspect, score);
              }
            }

            const ranked = rankAspects(state.scores);
            if (shouldNudge(Array.from(state.scores.values()), config.nudgeThreshold)) {
              const nudge = buildNudge(ranked);
              if (nudge) {
                logEvent("nudge", sessionID, `aspects=${ranked.slice(0, 3).join(",")}`);
              }
            }

            updateSessionState(sessionID, { aspects: ranked });

            // Mark success and update dedup tracker
            recordSuccess(sessionID);
            if (latestAssistantId) {
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
