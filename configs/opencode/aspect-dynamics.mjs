// configs/opencode/aspect-dynamics.mjs
// Aspect Dynamics config-layer plugin surface

import { loadConfig } from "./aspect-dynamics/config.mjs";
import { loadSets } from "./aspect-dynamics/sets.mjs";
import {
  getSessionState,
  updateSessionState,
  deleteSessionState,
} from "./aspect-dynamics/session-state.mjs";
import { extractContext, getEventSessionID } from "./aspect-dynamics/context.mjs";
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
          const state = getSessionState(sessionID);
          const context = await extractContext(ctx, sessionID);
          if (!context) {
            logWarn(`No context for session ${sessionID}`);
            return;
          }

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
          break;
        }

        default:
          break;
      }
    },
  };
}
