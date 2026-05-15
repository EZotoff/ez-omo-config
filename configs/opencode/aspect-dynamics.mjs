// configs/opencode/aspect-dynamics.mjs
// Aspect Dynamics config-layer plugin surface

import { loadConfig } from "./aspect-dynamics/config.mjs";
import { extractContext, getEventSessionID, hasRecursionGuard, prefilterContext } from "./aspect-dynamics/context.mjs";
import { rankAspects, scoreAspects, shouldNudge } from "./aspect-dynamics/heuristics.mjs";
import { emitProofEvent, initProofSink, logEvent, logInfo, logWarn } from "./aspect-dynamics/logging.mjs";
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

  const sets = await loadSets();

  initProofSink(config);

  logInfo("Plugin loaded");
  emitProofEvent("plugin_loaded", { status: "success" });

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
          emitProofEvent("session_created", { status: "success", session_id: sessionID });
          const child = await isChildSession(ctx, sessionID);
          if (child) {
            logWarn(`Child session ${sessionID} ignored — no aspect-dynamics tracking`);
            emitProofEvent("child_session_ignored", {
              status: "skipped",
              session_id: sessionID,
              reason: "Child session",
            });
            return;
          }
          getSessionState(sessionID);
          break;
        }

        case "session.deleted": {
          logEvent("session.deleted", sessionID);
          emitProofEvent("session_deleted", { status: "success", session_id: sessionID });
          deleteSessionState(sessionID);
          break;
        }

        case "session.idle": {
          logEvent("session.idle", sessionID);
          const idleStartMs = Date.now();
          emitProofEvent("idle_seen", { status: "idle", session_id: sessionID });

          const child = await isChildSession(ctx, sessionID);
          if (child) {
            logWarn(`Session ${sessionID} skipped — child session`);
            emitProofEvent("skip", {
              status: "skipped",
              session_id: sessionID,
              reason: "Child session",
              duration_ms: Date.now() - idleStartMs,
            });
            return;
          }

          if (!canProcess(sessionID)) {
            const state = getSessionState(sessionID);
            if (state.circuitBroken) {
              logWarn(`Session ${sessionID} skipped — circuit breaker open`);
              emitProofEvent("circuit_open", {
                status: "skipped",
                session_id: sessionID,
                reason: "Circuit breaker open",
                duration_ms: Date.now() - idleStartMs,
              });
            } else if (state.inFlight) {
              logWarn(`Session ${sessionID} skipped — action already in flight`);
              emitProofEvent("skip", {
                status: "skipped",
                session_id: sessionID,
                reason: "Action already in flight",
                duration_ms: Date.now() - idleStartMs,
              });
            }
            return;
          }

          markInFlight(sessionID, true);

          try {
            const context = await extractContext(ctx, sessionID, config);
            if (!context) {
              logWarn(`No context for session ${sessionID}`);
              recordFailure(sessionID);
              emitProofEvent("failure", {
                status: "failure",
                session_id: sessionID,
                error: "No context extracted",
                duration_ms: Date.now() - idleStartMs,
              });
              return;
            }

            if (hasRecursionGuard(context)) {
              logWarn(`Session ${sessionID} skipped — recursion guard detected aspect-dynamics nudge`);
              emitProofEvent("skip", {
                status: "skipped",
                session_id: sessionID,
                reason: "Recursion guard detected aspect-dynamics nudge",
                duration_ms: Date.now() - idleStartMs,
              });
              recordSuccess(sessionID);
              return;
            }

            // Prefilter: skip scoring if no heuristic phrases match
            if (!prefilterContext(context, sets, config)) {
              logEvent("session.idle", sessionID, "prefilter=skip");
              emitProofEvent("skip", {
                status: "skipped",
                session_id: sessionID,
                reason: "Prefilter miss",
                duration_ms: Date.now() - idleStartMs,
              });
              recordSuccess(sessionID);
              return;
            }

            // Deduplication: skip if already handled this assistant message
            const latestAssistantId = context.latestAssistantMessageId;
            const lastHandled = getLastHandledAssistantMessageId(sessionID);
            if (latestAssistantId && latestAssistantId === lastHandled) {
              logWarn(`Session ${sessionID} skipped — already handled assistant message ${latestAssistantId}`);
              emitProofEvent("skip", {
                status: "skipped",
                session_id: sessionID,
                reason: "Already handled assistant message",
                duration_ms: Date.now() - idleStartMs,
              });
              return;
            }

            const scoring = scoreAspects(context, sets);
            const ranked = rankAspects(scoring.allScores);

            const scoreEventData = {
              status: "success",
              session_id: sessionID,
              duration_ms: Date.now() - idleStartMs,
            };
            if (scoring.topScore >= 0) {
              scoreEventData.counts = { top_score: scoring.topScore };
            }
            emitProofEvent("score", scoreEventData);

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
                  emitProofEvent("nudge_sent", {
                    status: "success",
                    session_id: sessionID,
                    counts: {
                      score: scoring.topScore,
                      aspect_id: topEntry.aspectId,
                      set_id: topEntry.setId,
                    },
                    duration_ms: Date.now() - idleStartMs,
                  });
                }
              }
            }

            const state = getSessionState(sessionID);
            state.scores = new Map(scoring.allScores);

            updateSessionState(sessionID, { aspects: ranked });

            // Mark success and update dedup tracker
            recordSuccess(sessionID);
            if (latestAssistantId) {
              setLastHandledAssistantMessageId(sessionID, latestAssistantId);
            }
          } catch (err) {
            logWarn(`Error processing session.idle for ${sessionID}: ${err.message}`);
            emitProofEvent("failure", {
              status: "failure",
              session_id: sessionID,
              error: `${err.name}: ${err.message}`,
              duration_ms: Date.now() - idleStartMs,
            });
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
