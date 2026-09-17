// configs/opencode/skill-nudger.mjs
// Skill Nudger — config-layer plugin: deterministic tool-signal detection +
// ephemeral skill-suggestion nudges delivered via experimental.chat.messages.transform
//
// Signals (MVP, rules-only):
//   repeatedFailure  -> debugging skill
//   retryableError   -> register-retry-error skill (patterns from retry-errors.json)
//   portBinding      -> deployment skill
//   loop             -> step-back meta advisory (no skill)
//
// Delivery: pending nudge consumed on the next messages.transform call for the
// same session; the synthetic message is NOT persisted to the transcript
// (verified live 2026-08-15). Fires for both root and subagent sessions.

import { loadCatalog } from "./skill-nudger/catalog.mjs";
import { loadConfig } from "./skill-nudger/config.mjs";
import { emitProof, logInfo, logTiming, logWarn, nowMs, setLogLevel } from "./skill-nudger/logging.mjs";
import { RULES, agentAllowed, buildNudge, buildSyntheticMessage, ruleForSignal } from "./skill-nudger/nudge.mjs";
import { createSignalTracker } from "./skill-nudger/signals.mjs";
import {
  canNudge,
  deleteSessionState,
  recordFailure,
  recordNudge,
  recordSuccess,
} from "./skill-nudger/state.mjs";

const RULES_BY_ID = new Map(RULES.map((r) => [r.id, r]));

function sessionContextFromMessages(messages) {
  let sessionID = null;
  const agents = new Set();
  for (let i = messages.length - 1; i >= 0; i--) {
    const m = messages[i];
    if (!sessionID && m?.info?.sessionID) sessionID = m.info.sessionID;
    if (m?.info?.agent) agents.add(m.info.agent);
    if (sessionID && agents.size > 0 && i < messages.length - 3) break;
  }
  return { sessionID, agents: [...agents] };
}

export default async function skillNudgerPlugin(_ctx) {
  const config = await loadConfig();
  if (!config) {
    logWarn("No skillNudger config loaded; plugin running in no-op mode");
    return noopHooks();
  }

  setLogLevel(config.logLevel);

  if (config.enabled === false) {
    logWarn("skillNudger disabled in config; plugin running in no-op mode");
    return noopHooks();
  }

  const catalog = loadCatalog();
  const tracker = createSignalTracker(config);
  // sessionID -> { ruleId, part, ts, agentsAtQueue }
  const pending = new Map();
  const pendingAcceptance = new Map();
  const assistantTurns = new Map();

  logInfo("Plugin loaded");
  emitProof("plugin_loaded", { version: "1.0.0", catalog_size: catalog.size });

  return {
    "tool.execute.after": async (input, output) => {
      const startedAt = nowMs();
      let signalCount = 0;
      try {
        const { sessionID, tool, args } = input ?? {};
        if (!sessionID) return;

        const acceptance = pendingAcceptance.get(sessionID);
        if (acceptance) {
          const loadedSkill = tool === "skill" ? args?.name ?? args?.skill ?? args?.skillName : null;
          const elapsedTurns = (assistantTurns.get(sessionID) ?? acceptance.deliveredAtTurn) - acceptance.deliveredAtTurn;
          if (loadedSkill === acceptance.skill && elapsedTurns <= 3) {
            emitProof("nudge_accepted", { session_id: sessionID, rule: acceptance.ruleId, skill: acceptance.skill });
            pendingAcceptance.delete(sessionID);
          } else if (elapsedTurns >= 3) {
            emitProof("nudge_ignored", { session_id: sessionID, rule: acceptance.ruleId });
            pendingAcceptance.delete(sessionID);
          }
        }

        const signals = tracker.observe({
          sessionID,
          tool,
          args,
          outputText: typeof output?.output === "string" ? output.output : "",
        });
        signalCount = signals.length;
        if (signals.length === 0) return;

        for (const signal of signals) {
          if (config.disabledSignals.includes(signal.type)) continue;

          const rule = ruleForSignal(signal.type);
          if (!rule) continue;

          const total = tracker.totalCalls(sessionID);
          const verdict = canNudge(sessionID, rule.id, config, total);
          if (!verdict.ok) {
            emitProof("skip", { session_id: sessionID, rule: rule.id, reason: verdict.reason });
            continue;
          }

          const part = buildNudge(rule, signal, catalog);
          pending.set(sessionID, { ruleId: rule.id, part, ts: Date.now() });
          recordNudge(sessionID, rule.id, total);
          recordSuccess(sessionID);
          emitProof("nudge_queued", {
            session_id: sessionID,
            rule: rule.id,
            signal: signal.type,
            evidence: signal.evidence,
          });
          logInfo(`Queued ${rule.id} nudge for session ${sessionID}`);
        }
      } catch (err) {
        const sid = input?.sessionID ?? "unknown";
        logWarn(`tool.execute.after error for ${sid}: ${err?.message ?? err}`);
        recordFailure(sid);
        emitProof("failure", { session_id: sid, hook: "tool.execute.after", error: String(err?.message ?? err) });
      } finally {
        // Stable metric: hook=tool.execute.after dur_ms=<n> signals=<n>
        logTiming("tool.execute.after", startedAt, `signals=${signalCount}`);
      }
    },

    "experimental.chat.messages.transform": async (_input, output) => {
      const startedAt = nowMs();
      try {
        const messages = output?.messages;
        if (!Array.isArray(messages) || messages.length === 0) return;

        const { sessionID, agents } = sessionContextFromMessages(messages);
        if (!sessionID) return;
        const assistantTurn = messages.filter((message) => message?.info?.role === "assistant").length;
        assistantTurns.set(sessionID, assistantTurn);

        const queued = pending.get(sessionID);
        if (!queued) return;
        pending.delete(sessionID);

        // Freshness window: drop stale nudges (e.g. queued during a long turn)
        if (Date.now() - queued.ts > config.freshnessMs) {
          emitProof("skip", { session_id: sessionID, rule: queued.ruleId, reason: "stale" });
          return;
        }

        // Per-agent scoping: if the rule has an agent allowlist, the session
        // must be running one of those agents (case-insensitive).
        const rule = RULES_BY_ID.get(queued.ruleId);
        if (rule && !agentAllowed(rule, agents)) {
          emitProof("skip", { session_id: sessionID, rule: queued.ruleId, reason: "agent_not_allowed" });
          return;
        }

        messages.push(buildSyntheticMessage(sessionID, queued.part));
        emitProof("nudge_delivered", { session_id: sessionID, rule: queued.ruleId, agents });
        if (rule?.skill) {
          pendingAcceptance.set(sessionID, { ruleId: queued.ruleId, skill: rule.skill, deliveredAtTurn: assistantTurn });
        }
        logInfo(`Delivered ${queued.ruleId} nudge to session ${sessionID} (agents: ${agents.join(",") || "?"})`);
      } catch (err) {
        const { sessionID } = sessionContextFromMessages(output?.messages ?? []);
        logWarn(`messages.transform error${sessionID ? ` for ${sessionID}` : ""}: ${err?.message ?? err}`);
        if (sessionID) recordFailure(sessionID);
        emitProof("failure", { session_id: sessionID ?? "unknown", hook: "messages.transform", error: String(err?.message ?? err) });
      } finally {
        // Stable metric: hook=messages.transform dur_ms=<n>
        logTiming("messages.transform", startedAt);
      }
    },

    event: async ({ event }) => {
      const type = event?.type;
      if (type !== "session.deleted") return;
      const sessionID = event?.properties?.sessionID ?? event?.properties?.id;
      if (!sessionID) return;
      tracker.deleteSession(sessionID);
      deleteSessionState(sessionID);
      pending.delete(sessionID);
      pendingAcceptance.delete(sessionID);
      assistantTurns.delete(sessionID);
      emitProof("session_cleanup", { session_id: sessionID });
    },
  };
}

function noopHooks() {
  return {
    "tool.execute.after": async () => {},
    "experimental.chat.messages.transform": async () => {},
    event: async () => {},
  };
}
