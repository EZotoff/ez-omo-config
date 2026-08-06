import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const REGISTRY_PATH = path.join(os.homedir(), ".config", "opencode", "retry-errors.json");
const LOG_PATH = path.join(os.homedir(), ".config", "opencode", "retry-plugin.log");
const OMO_CONFIG_PATH = path.join(os.homedir(), ".config", "opencode", "oh-my-openagent.json");
const LOG_MAX_BYTES = 10 * 1024 * 1024; // 10 MB before rotation

function rotateLogIfNeeded() {
  try {
    const stat = fs.statSync(LOG_PATH);
    if (stat.size > LOG_MAX_BYTES) {
      const backup = `${LOG_PATH}.1`;
      try { fs.unlinkSync(backup); } catch {}
      try { fs.renameSync(LOG_PATH, backup); } catch { try { fs.unlinkSync(LOG_PATH); } catch {} }
    }
  } catch {
    // file doesn't exist yet — nothing to rotate
  }
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

function log(level, msg) {
  const ts = new Date().toISOString();
  const line = `[${ts}] [${level}] ${msg}\n`;
  try { rotateLogIfNeeded(); fs.appendFileSync(LOG_PATH, line); } catch {}
  // User-facing output MUST go through ctx.client.tui.showToast (see surfaceToast helper).
  // console.warn/info would leak into the TUI viewport / journald as raw spam.
}

async function surfaceToast(ctx, { title, message, variant = "info", duration = 5000 }) {
  // Publishes a tui.toast.show event via POST /tui/show-toast. The TUI subscribes
  // (packages/tui/src/app.tsx:990) and renders a real toast popup. Safe to call
  // unconditionally — if no TUI is connected the event is silently dropped.
  try {
    await ctx.client.tui.showToast({
      body: { ...(title ? { title } : {}), message, variant, duration },
    });
  } catch (error) {
    log("warn", `Toast call failed: ${error?.message ?? error}; intended message: ${message}`);
  }
}


function loadRegistry() {
  try {
    const content = fs.readFileSync(REGISTRY_PATH, "utf8");
    const registry = JSON.parse(content);
    if (!Array.isArray(registry?.errors)) return [];

    return registry.errors.flatMap((entry) => {
      try {
        if (typeof entry?.pattern !== "string" || entry.pattern.length === 0) return [];

        return [{
          ...entry,
          compiledPattern: new RegExp(entry.pattern, "i"),
        }];
      } catch (error) {
        log("warn", `Skipping invalid registry rule "${entry?.id ?? "unknown"}": ${error?.message ?? error}`);
        return [];
      }
    });
  } catch (error) {
    log("warn", `Failed to load registry: ${error?.message ?? error}`);
    return [];
  }
}

function findMatchingRule(errorMessage, registry) {
  return registry.find((entry) => entry.compiledPattern.test(errorMessage));
}

function getErrorMessage(error) {
  if (!error) return "";
  if (typeof error === "string") return error.toLowerCase();
  if (error instanceof Error) return (error.message || String(error)).toLowerCase();

  const candidates = [error, error.data, error.error, error.cause, error.data?.error];
  for (const candidate of candidates) {
    if (candidate && typeof candidate === "object" && typeof candidate.message === "string" && candidate.message.length > 0) {
      return candidate.message.toLowerCase();
    }
  }

  try {
    return JSON.stringify(error).toLowerCase();
  } catch {
    return String(error).toLowerCase();
  }
}

function sanitizePromptParts(parts) {
  if (!Array.isArray(parts)) return [];

  return parts
    .map((part) => {
      if (!part || typeof part !== "object") return null;

      if (part.type === "text" && typeof part.text === "string" && part.text.length > 0) {
        return { type: "text", text: part.text };
      }

      if (part.type === "file" && typeof part.mime === "string" && typeof part.url === "string") {
        return {
          type: "file",
          mime: part.mime,
          url: part.url,
          ...(typeof part.filename === "string" ? { filename: part.filename } : {}),
          ...(part.source ? { source: part.source } : {}),
        };
      }

      if (part.type === "agent" && typeof part.name === "string" && part.name.length > 0) {
        return {
          type: "agent",
          name: part.name,
          ...(part.source ? { source: part.source } : {}),
        };
      }

      if (part.type === "subtask" && typeof part.prompt === "string" && typeof part.description === "string" && typeof part.agent === "string") {
        return {
          type: "subtask",
          prompt: part.prompt,
          description: part.description,
          agent: part.agent,
          ...(part.model ? { model: part.model } : {}),
          ...(typeof part.command === "string" ? { command: part.command } : {}),
        };
      }

      return null;
    })
    .filter(Boolean);
}

function fingerprintParts(parts) {
  return JSON.stringify(parts);
}

function getNudgePromptParts(rule, agentName, attemptIndex) {
  const nudge = rule.nudge_prompts;
  if (!nudge || typeof nudge !== "object") return undefined;

  const agentKey = typeof agentName === "string" ? agentName.toLowerCase() : "";
  const prompts = nudge[agentKey] ?? nudge.default;
  if (!Array.isArray(prompts) || prompts.length === 0) return undefined;

  const idx = Math.min(attemptIndex, prompts.length - 1);
  const text = prompts[idx];
  if (typeof text !== "string" || text.length === 0) return undefined;

  return [{ type: "text", text }];
}

function buildAttemptState({
  tracked,
  fingerprint,
  retryParts,
  retryMessageID,
  attempts,
  ruleID,
  nudgeParts,
  lastSessionStatusRetryKey,
}) {
  const nudgeFingerprint = Array.isArray(nudgeParts) ? fingerprintParts(nudgeParts) : undefined;
  return {
    fingerprint: nudgeFingerprint ?? fingerprint,
    originalFingerprint: tracked?.originalFingerprint ?? fingerprint,
    originalParts: tracked?.originalParts ?? retryParts,
    originalMessageID: tracked?.originalMessageID ?? retryMessageID,
    attempts,
    ruleID,
    userMessageID: nudgeFingerprint ? undefined : retryMessageID,
    pendingNudge: Boolean(nudgeFingerprint),
    pendingNudgeFingerprint: nudgeFingerprint,
    emptyCompletionDetected: false,
    emptyMessageID: undefined,
    ...(lastSessionStatusRetryKey ? { lastSessionStatusRetryKey } : {}),
  };
}

function getEventSessionID(event) {
  const props = event?.properties ?? {};
  return props.sessionID ?? props.info?.sessionID;
}

function getEventError(event) {
  const props = event?.properties ?? {};
  if (event?.type === "session.error") return props.error;
  if (event?.type === "message.updated" && props.info?.role === "assistant") return props.info?.error;
  return undefined;
}

function getEventParentID(event) {
  const props = event?.properties ?? {};
  return props.parentID ?? props.info?.parentID;
}

function getEventAgent(event, messages) {
  const props = event?.properties ?? {};
  const direct = props.agent ?? props.info?.agent;
  if (typeof direct === "string" && direct.length > 0) return direct;

  for (let i = messages.length - 1; i >= 0; i -= 1) {
    const agent = messages[i]?.info?.agent;
    if (typeof agent === "string" && agent.length > 0) return agent;
  }

  return undefined;
}

function getEventModel(event, messages) {
  const props = event?.properties ?? {};
  const providerID = props.providerID ?? props.info?.providerID;
  const modelID = props.modelID ?? props.info?.modelID;
  if (typeof providerID === "string" && typeof modelID === "string" && providerID.length > 0 && modelID.length > 0) {
    return { providerID, modelID };
  }

  for (let i = messages.length - 1; i >= 0; i -= 1) {
    const info = messages[i]?.info;
    if (typeof info?.providerID === "string" && typeof info?.modelID === "string" && info.providerID.length > 0 && info.modelID.length > 0) {
      return { providerID: info.providerID, modelID: info.modelID };
    }
  }

  return undefined;
}

function getFailedAssistantMessageID(event, messages) {
  const props = event?.properties ?? {};
  const direct = props.messageID ?? props.info?.id;
  if (typeof direct === "string" && direct.length > 0) return direct;

  for (let i = messages.length - 1; i >= 0; i -= 1) {
    const info = messages[i]?.info;
    if (info?.role === "assistant" && info?.error && typeof info.id === "string" && info.id.length > 0) {
      return info.id;
    }
  }

  return undefined;
}

function getMessageID(message) {
  const direct = message?.id ?? message?.messageID;
  if (typeof direct === "string" && direct.length > 0) return direct;

  const infoID = message?.info?.id;
  if (typeof infoID === "string" && infoID.length > 0) return infoID;

  return undefined;
}

function getLastUserMessageIndex(messages) {
  for (let i = messages.length - 1; i >= 0; i -= 1) {
    const role = messages[i]?.info?.role ?? messages[i]?.role;
    if (role === "user") return i;
  }

  return -1;
}

function getLastAssistantMessage(messages) {
  for (let i = messages.length - 1; i >= 0; i -= 1) {
    const role = messages[i]?.info?.role ?? messages[i]?.role;
    if (role === "assistant") return messages[i];
  }

  return undefined;
}

function messageHasToolExecution(message) {
  const role = message?.info?.role ?? message?.role;
  if (role === "tool") return true;

  const parts = message?.parts ?? message?.info?.parts;
  if (Array.isArray(parts)) {
    for (const part of parts) {
      if (!part || typeof part !== "object") continue;

      const type = typeof part.type === "string" ? part.type.toLowerCase() : "";
      if (type.includes("tool")) return true;

      if (
        typeof part.tool === "string"
        || typeof part.toolName === "string"
        || typeof part.callID === "string"
        || typeof part.toolCallID === "string"
      ) {
        return true;
      }
    }
  }

  const info = message?.info;
  return Boolean(
    typeof info?.tool === "string"
    || typeof info?.toolName === "string"
    || typeof info?.callID === "string"
    || typeof info?.toolCallID === "string",
  );
}

function hasToolExecutionSinceLastUser(messages, lastUserMessageIndex) {
  if (lastUserMessageIndex < 0) return false;

  for (let i = lastUserMessageIndex + 1; i < messages.length; i += 1) {
    if (messageHasToolExecution(messages[i])) return true;
  }

  return false;
}

function clearSessionState(sessionID, attemptsBySession, handledErrorsBySession) {
  attemptsBySession.delete(sessionID);
  handledErrorsBySession.delete(sessionID);
}

function parseFallbackModel(fallbackModel) {
  if (typeof fallbackModel !== "string" || fallbackModel.length === 0) return undefined;
  const slashIndex = fallbackModel.indexOf("/");
  if (slashIndex <= 0 || slashIndex >= fallbackModel.length - 1) return undefined;
  return {
    providerID: fallbackModel.substring(0, slashIndex),
    modelID: fallbackModel.substring(slashIndex + 1),
  };
}

function loadOmoConfig() {
  try {
    return JSON.parse(fs.readFileSync(OMO_CONFIG_PATH, "utf8"));
  } catch (error) {
    log("warn", `Failed to load OMO config for agent fallback resolution: ${error?.message ?? error}`);
    return undefined;
  }
}

// Resolve the fallback model for a session by deferring to the agent's (or
// governing category's) canonical fallback_models chain in oh-my-openagent.json.
// One source of truth for which model to fall back to — replaces the former
// per-rule fallback_model field that drifted out of sync on every rebalance
// (root cause of the 2026-07-21 K3 self-fallback incident).
//
// Resolution order mirrors OMO's model-resolution precedence (category model
// takes precedence over agent model when a category override is in effect):
//   1. If the failing model matches the named agent's primary model, use that
//      agent's fallback_models chain.
//   2. Otherwise (likely a category-spawned session), find the category whose
//      primary model matches the failing model and use its chain.
//   3. Last resort: the named agent's chain even on mismatch (still a valid chain).
//
// The first chain entry whose provider differs from the failing provider is
// returned (parsed via parseFallbackModel); same-provider entries are skipped,
// so self-fallback is structurally impossible. Returns undefined if no usable entry.
function resolveAgentFallback(agentName, failingModel) {
  if (!failingModel?.providerID) return undefined;
  const config = loadOmoConfig();
  if (!config) return undefined;

  const failingModelStr = failingModel.modelID
    ? `${failingModel.providerID}/${failingModel.modelID}`
    : undefined;

  const pickFromChain = (chain) => {
    if (!Array.isArray(chain)) return undefined;
    for (const entry of chain) {
      if (typeof entry !== "string") continue;
      const parsed = parseFallbackModel(entry);
      if (parsed && parsed.providerID !== failingModel.providerID) return parsed;
    }
    return undefined;
  };

  const agents = config.agents && typeof config.agents === "object" ? config.agents : {};
  const categories = config.categories && typeof config.categories === "object" ? config.categories : {};
  const agentBlock = typeof agentName === "string" ? agents[agentName] : undefined;

  // 1. Agent chain when its primary model matches the failing model.
  if (agentBlock && failingModelStr && agentBlock.model === failingModelStr) {
    const picked = pickFromChain(agentBlock.fallback_models);
    if (picked) return picked;
  }

  // 2. Category override: find the category whose model matches.
  if (failingModelStr) {
    for (const catName of Object.keys(categories)) {
      const cat = categories[catName];
      if (cat && cat.model === failingModelStr) {
        const picked = pickFromChain(cat.fallback_models);
        if (picked) return picked;
      }
    }
  }

  // 3. Last resort: the agent's chain even on model mismatch.
  if (agentBlock) {
    const picked = pickFromChain(agentBlock.fallback_models);
    if (picked) return picked;
  }

  return undefined;
}

function isEmptyAssistantMessage(message) {
  const info = message?.info ?? message;
  if ((info?.role ?? message?.role) !== "assistant") return false;
  if (info?.error) return false;

  const parts = info?.parts ?? message?.parts;
  // If the model never produced ANY parts at all, that's a true stall (zero tokens).
  if (!Array.isArray(parts) || parts.length === 0) return true;

  // If parts exist, check whether any part has actual content.
  // A genuine empty completion (finish="other", output=0) may still have an
  // empty text placeholder from OpenCode, but no tool calls and no non-empty text.
  // A user Ctrl+C interrupt that produced partial tokens would have output > 0
  // and was already excluded by the detection check (finish === "other" && output === 0).
  const hasContent = parts.some((part) => {
    if (!part || typeof part !== "object") return false;
    const type = typeof part.type === "string" ? part.type.toLowerCase() : "";
    if (type === "text" && typeof part.text === "string" && part.text.trim().length > 0) return true;
    if (type.includes("tool")) return true;
    if (typeof part.tool === "string" || typeof part.toolName === "string") return true;
    return false;
  });

  return !hasContent;
}

function findEmptyResponseRule(registry) {
  return registry.find((entry) => entry.nudge_prompts && entry.detect_empty_response);
}

export const ProviderConnectRetryPlugin = async (ctx) => {
  const attemptsBySession = new Map();
  const inFlightSessions = new Set();
  const handledErrorsBySession = new Map();
  const childSessionVerdictCache = new Map();

  globalThis.__providerConnectRetryInFlight = inFlightSessions;
  log("info", `ProviderConnectRetryPlugin initialized (pid ${process.pid}, log ${LOG_PATH})`);



  return {
    event: async ({ event }) => {
      const sessionID = getEventSessionID(event);
      if (!sessionID) return;

      if (event?.type === "session.idle") {
        if (inFlightSessions.has(sessionID)) return;

        const tracked = attemptsBySession.get(sessionID);
        // Only dispatch empty-response retry if message.updated flagged a
        // clean empty completion (not a user Ctrl+C abort).
        if (tracked?.emptyCompletionDetected) {
          const registry = loadRegistry();
          const emptyRule = findEmptyResponseRule(registry);
          if (emptyRule) {
            inFlightSessions.add(sessionID);
            try {
              const messagesResponse = await ctx.client.session.messages({
                path: { id: sessionID },
                ...(ctx.directory ? { query: { directory: ctx.directory } } : {}),
              }).catch(() => null);
              const messages = Array.isArray(messagesResponse?.data) ? messagesResponse.data : [];
              const lastAssistantMessage = getLastAssistantMessage(messages);
              const lastAssistantMessageID = getMessageID(lastAssistantMessage);

              if (tracked.emptyMessageID && tracked.emptyMessageID !== lastAssistantMessageID) {
                log("warn", `Empty-response guard: message ID mismatch (tracked=${tracked.emptyMessageID}, last=${lastAssistantMessageID}) — clearing state`);
                clearSessionState(sessionID, attemptsBySession, handledErrorsBySession);
                return;
              }

              const neMsgTokens = lastAssistantMessage?.info?.tokens?.output;
              const neTrackedNearEmpty = tracked?.extra?.nearEmpty === true;
              const neMinTokens = tracked?.extra?.minOutputTokens;
              const isNearEmptyMessage = neTrackedNearEmpty
                && typeof neMsgTokens === "number"
                && neMsgTokens > 0
                && typeof neMinTokens === "number"
                && neMsgTokens <= neMinTokens;
              if (neTrackedNearEmpty && typeof neMsgTokens !== "number") {
                log("debug", `Near-empty guard: tracked.extra.nearEmpty=true but stored message lacks info.tokens.output — skipping near-empty path for session ${sessionID}`);
              }
              if (!isEmptyAssistantMessage(lastAssistantMessage) && !isNearEmptyMessage) {
                const parts = lastAssistantMessage?.info?.parts ?? lastAssistantMessage?.parts;
                log("warn", `Empty-response guard: last assistant message has content (parts=${JSON.stringify(parts)?.substring(0, 200)}) — clearing state`);
                clearSessionState(sessionID, attemptsBySession, handledErrorsBySession);
                return;
              }

              const lastUserMessageIndex = getLastUserMessageIndex(messages);
              const lastUserMessage = lastUserMessageIndex >= 0 ? messages[lastUserMessageIndex] : undefined;
              const retryParts = sanitizePromptParts(lastUserMessage?.parts ?? lastUserMessage?.info?.parts);
              const retryMessageID = getMessageID(lastUserMessage);

              if (retryParts.length > 0) {
                const fingerprint = fingerprintParts(retryParts);
                const nextAttempt = (tracked.ruleID === emptyRule.id && (tracked.fingerprint === fingerprint || tracked.originalFingerprint === fingerprint))
                  ? (tracked.attempts ?? 0) + 1 : 1;
                const attemptIndex = nextAttempt - 1;

                const agent = getEventAgent(event, messages) ?? lastUserMessage?.info?.agent;
                const model = getEventModel(event, messages) ?? lastUserMessage?.info?.model;
                const system = typeof lastUserMessage?.info?.system === "string" ? lastUserMessage.info.system : undefined;
                const tools = lastUserMessage?.info?.tools && typeof lastUserMessage.info.tools === "object" ? lastUserMessage.info.tools : undefined;
                const variant = typeof lastUserMessage?.info?.variant === "string" ? lastUserMessage.info.variant : undefined;

                if (nextAttempt > emptyRule.max_retries || attemptIndex >= emptyRule.backoff_ms.length) {
                  const fallback = resolveAgentFallback(agent, model);
                  if (fallback) {
                    const fallbackParts = tracked.originalParts ?? retryParts;
                    const fallbackMessageID = tracked.originalMessageID ?? retryMessageID;
                    log("info", `Exhausted empty-response retries for "${emptyRule.id}" — falling back to ${fallback.providerID}/${fallback.modelID} via agent "${agent ?? "unknown"}" chain`);
                    await sleep(1000);
                    await ctx.client.session.promptAsync({
                      path: { id: sessionID },
                      ...(ctx.directory ? { query: { directory: ctx.directory } } : {}),
                      body: {
                        ...(fallbackMessageID ? { messageID: fallbackMessageID } : {}),
                        ...(agent ? { agent } : {}),
                        model: fallback,
                        ...(system ? { system } : {}),
                        ...(tools ? { tools } : {}),
                        parts: fallbackParts,
                      },
                    });
                  } else {
                    const failingProviderID = model?.providerID ?? "unknown";
                    log("warn", `Exhausted empty-response retries for "${emptyRule.id}" — no fallback in agent "${agent ?? "unknown"}" chain for provider "${failingProviderID}"`);
                    await surfaceToast(ctx, {
                      title: "Retries exhausted",
                      message: `Rule "${emptyRule.id}" exhausted ${emptyRule.max_retries} empty-response retries; agent "${agent ?? "unknown"}" has no fallback chain for provider "${failingProviderID}".`,
                      variant: "warning",
                      duration: 10000,
                    });
                  }
                } else {
                  const delayMs = emptyRule.backoff_ms[attemptIndex];
                  const nudgeParts = getNudgePromptParts(emptyRule, agent, attemptIndex);
                  const useNudge = Boolean(nudgeParts);
                  const dispatchParts = useNudge ? nudgeParts : retryParts;

                  log("info", `Empty-response retry ${nextAttempt}/${emptyRule.max_retries} for "${emptyRule.id}" in ${delayMs}ms`);
                  if (useNudge) {
                    log("info", `Sending nudge prompt (attempt ${nextAttempt}): "${nudgeParts[0].text.substring(0, 60)}..."`);
                  }

                  await ctx.client.session.abort({
                    path: { id: sessionID },
                    ...(ctx.directory ? { query: { directory: ctx.directory } } : {}),
                  }).catch(() => {});
                  await sleep(delayMs);
                  await ctx.client.session.promptAsync({
                    path: { id: sessionID },
                    ...(ctx.directory ? { query: { directory: ctx.directory } } : {}),
                    body: {
                      ...(!useNudge && retryMessageID ? { messageID: retryMessageID } : {}),
                      ...(agent ? { agent } : {}),
                      ...(model ? { model } : {}),
                      ...(system ? { system } : {}),
                      ...(tools ? { tools } : {}),
                      ...(variant ? { variant } : {}),
                      parts: dispatchParts,
                    },
                  });
                  log("info", `Dispatched empty-response retry ${nextAttempt}/${emptyRule.max_retries} for "${emptyRule.id}"`);
                  attemptsBySession.set(sessionID, buildAttemptState({
                    tracked,
                    fingerprint,
                    retryParts,
                    retryMessageID,
                    attempts: nextAttempt,
                    ruleID: emptyRule.id,
                    nudgeParts: useNudge ? nudgeParts : undefined,
                  }));
                }
              }
            } catch (dispatchError) {
              log("warn", `Failed to dispatch empty-response retry: ${dispatchError?.message ?? dispatchError}`);
              await surfaceToast(ctx, {
                title: "Retry dispatch failed",
                message: `Failed to dispatch empty-response retry for rule "${emptyRule?.id ?? "unknown"}": ${dispatchError?.message ?? dispatchError}`,
                variant: "error",
                duration: 10000,
              });
            } finally {
              inFlightSessions.delete(sessionID);
            }
            return;
          }
        }
        clearSessionState(sessionID, attemptsBySession, handledErrorsBySession);
        return;
      }

      if (event?.type === "message.updated") {
        const info = event.properties?.info ?? {};

        // Detect GLM stalls via finish-reason on assistant message.updated.
        // OpenCode exposes `finish` field on completion events:
        //   - "tool-calls" or "stop" → normal completion
        //   - "other" + tokens.output === 0 → model stalled (zero tokens)
        //   - no `finish` → intermediate streaming update, ignore
        if (info.role === "assistant" && !info.error) {
          const finish = info.finish;
          const tokens = info.tokens ?? {};
          const msgID = typeof info.id === "string" && info.id.length > 0 ? info.id : undefined;

          if (finish) {
            // This is a COMPLETION event (model finished generating).
            // Catch both "other" (stall) and "stop" (silent stop) with zero output tokens.
            // GLM-5.2 on context saturation returns finish="stop" with 0 tokens.
            // The 2026-04-18 narrowing (commit 36947f9) excluded "stop" to avoid false
            // positives, but legitimate stop completions always have output > 0.
            if ((finish === "other" || finish === "stop") && (tokens.output ?? 0) === 0) {
              // Model returned zero output tokens → STALL (context saturation or API issue)
              const registry = loadRegistry();
              const emptyRule = findEmptyResponseRule(registry);
              if (emptyRule && !inFlightSessions.has(sessionID)) {
                const alreadyHandled = msgID && handledErrorsBySession.get(sessionID) === msgID;
                if (!alreadyHandled) {
                  log("info", `Session ${sessionID}: detected empty completion (finish="${finish}", output=${tokens.output}) — flagging for retry`);
                  const tracked = attemptsBySession.get(sessionID);
                  attemptsBySession.set(sessionID, {
                    ...(tracked ?? {}),
                    ruleID: emptyRule.id,
                    emptyCompletionDetected: true,
                    emptyMessageID: msgID,
                  });
                  handledErrorsBySession.set(sessionID, msgID ?? "__empty__");
                }
              }
            } else if ((finish === "other" || finish === "stop") && (tokens.output ?? 0) > 0) {
              // NEAR-EMPTY CANDIDATE: finish="other"|"stop" with output > 0 tokens.
              // Either a near-empty stall on a child session (flag for retry) or a
              // legitimate normal stop with content (clear stale tracking).
              const outputTokens = tokens.output;
              const registry = loadRegistry();
              const emptyRule = findEmptyResponseRule(registry);
              const minTokens = typeof emptyRule?.min_output_tokens === "number" ? emptyRule.min_output_tokens : 5;
              const isNearEmpty = minTokens > 0 && outputTokens <= minTokens;
              if (emptyRule && isNearEmpty && !inFlightSessions.has(sessionID)) {
                const alreadyHandled = msgID && handledErrorsBySession.get(sessionID) === msgID;
                if (!alreadyHandled) {
                  // Resolve child-session status, cached per sessionID to avoid one API call per completion.
                  let isChildSession = childSessionVerdictCache.get(sessionID);
                  if (isChildSession === undefined) {
                    const sessionInfo = await ctx.client.session.get({ path: { id: sessionID } }).catch(() => undefined);
                    const parentID = sessionInfo?.data?.parentID ?? sessionInfo?.parentID;
                    isChildSession = typeof parentID === "string" && parentID.length > 0;
                    childSessionVerdictCache.set(sessionID, isChildSession);
                  }
                  if (!isChildSession) {
                    log("debug", `Near-empty completion on session ${sessionID} (output=${outputTokens}, threshold=${minTokens}) — no parentID, skipping`);
                  } else {
                    log("info", `near-empty completion flagged (output=${outputTokens} tokens, threshold=${minTokens}, child session)`);
                    const tracked = attemptsBySession.get(sessionID);
                    attemptsBySession.set(sessionID, {
                      ...(tracked ?? {}),
                      ruleID: emptyRule.id,
                      emptyCompletionDetected: true,
                      emptyMessageID: msgID,
                      extra: {
                        ...(tracked?.extra ?? {}),
                        minOutputTokens: minTokens,
                        nearEmpty: true,
                      },
                    });
                    handledErrorsBySession.set(sessionID, msgID ?? "__empty__");
                  }
                }
              } else {
                // Legitimate normal stop with output > threshold — clear stale tracking.
                const tracked = attemptsBySession.get(sessionID);
                attemptsBySession.set(sessionID, {
                  ...(tracked ?? {}),
                  emptyCompletionDetected: false,
                });
              }
            } else {
              // Normal completion (tool-calls, stop, etc.) — clear any stale tracking
              const tracked = attemptsBySession.get(sessionID);
              attemptsBySession.set(sessionID, {
                ...(tracked ?? {}),
                emptyCompletionDetected: false,
              });
            }
          }
          // If no `finish` field → intermediate update, ignore entirely
          return;
        }

        if (info.role === "user") {
          const currentParts = sanitizePromptParts(event.properties?.parts ?? info.parts);
          if (currentParts.length > 0) {
            const nextFingerprint = fingerprintParts(currentParts);
            const nextMessageID = typeof info.id === "string" && info.id.length > 0 ? info.id : undefined;
            const existing = attemptsBySession.get(sessionID);
            const isPendingNudge = existing?.pendingNudge === true && existing?.pendingNudgeFingerprint === nextFingerprint;
            if (isPendingNudge) {
              attemptsBySession.set(sessionID, {
                ...existing,
                fingerprint: nextFingerprint,
                userMessageID: nextMessageID,
                pendingNudge: false,
                pendingNudgeFingerprint: undefined,
                emptyCompletionDetected: false,
              });
              return;
            }
            if (!existing || existing.fingerprint !== nextFingerprint || existing.userMessageID !== nextMessageID) {
              attemptsBySession.set(sessionID, { fingerprint: nextFingerprint, attempts: 0, userMessageID: nextMessageID });
              handledErrorsBySession.delete(sessionID);
            }
          }
          return;
        }
      }

      if (event?.type !== "session.error" && event?.type !== "message.updated") return;

      const error = getEventError(event);
      const errorMessage = getErrorMessage(error);
      const registry = loadRegistry();
      const matchedRule = findMatchingRule(errorMessage, registry);
      if (!matchedRule) return;
      log("info", `Error matched rule "${matchedRule.id}": ${errorMessage.substring(0, 100)}`);
      if (inFlightSessions.has(sessionID)) return;
      const originalAttemptState = attemptsBySession.get(sessionID);
      inFlightSessions.add(sessionID);
      let previousAttemptState = originalAttemptState;

      try {
        const sessionResponse = await ctx.client.session.get({
          path: { id: sessionID },
          ...(ctx.directory ? { query: { directory: ctx.directory } } : {}),
        }).catch(() => null);

        const parentID = getEventParentID(event) ?? sessionResponse?.data?.parentID;
        const isChildSession = typeof parentID === "string" && parentID.length > 0;

        const messagesResponse = await ctx.client.session.messages({
          path: { id: sessionID },
          ...(ctx.directory ? { query: { directory: ctx.directory } } : {}),
        }).catch(() => null);

        const messages = Array.isArray(messagesResponse?.data) ? messagesResponse.data : [];
        const agent = getEventAgent(event, messages);
        const model = getEventModel(event, messages);

        // Child-session gate: skip sessions whose agent has no recoverable
        // fallback chain. Under unified fallback, recovery viability depends on
        // the agent's chain in oh-my-openagent.json — not a per-rule field. The
        // resolved agentFallback is reused at the exhaustion dispatch below.
        const agentFallback = resolveAgentFallback(agent, model);
        if (isChildSession && !agentFallback) {
          log(
            "info",
            `Skipping retry for child session ${sessionID} (agent "${agent ?? "unknown"}" has no fallback chain for failing provider "${model?.providerID ?? "unknown"}")`,
          );
          return;
        }
        if (isChildSession) {
          log(
            "info",
            `Child session ${sessionID} entering retry path (agent "${agent ?? "unknown"}" fallback → ${agentFallback.providerID}/${agentFallback.modelID})`,
          );
        }

        const failedAssistantMessageID = getFailedAssistantMessageID(event, messages);
        if (!failedAssistantMessageID) {
          log("warn", `Skipping retry for "${matchedRule.id}" — no failed assistant message ID available`);
          return;
        }
        if (handledErrorsBySession.get(sessionID) === failedAssistantMessageID) return;

        const lastUserMessageIndex = getLastUserMessageIndex(messages);
        const lastUserMessage = lastUserMessageIndex >= 0 ? messages[lastUserMessageIndex] : undefined;
        const retryParts = sanitizePromptParts(lastUserMessage?.parts ?? lastUserMessage?.info?.parts);
        if (retryParts.length === 0) return;
        const retryMessageID = getMessageID(lastUserMessage);

        if (!matchedRule.retry_after_tool_execution && hasToolExecutionSinceLastUser(messages, lastUserMessageIndex)) {
          handledErrorsBySession.set(sessionID, failedAssistantMessageID);
          log("warn", `Skipping retry for "${matchedRule.id}" — tool execution detected in session`);
          return;
        }

        const fingerprint = fingerprintParts(retryParts);
        const current = attemptsBySession.get(sessionID);
        const hasNudge = Boolean(matchedRule.nudge_prompts);
        const nextAttempt = current
          && current.ruleID === matchedRule.id
          && (current.fingerprint === fingerprint || (hasNudge && current.originalFingerprint === fingerprint))
          ? current.attempts + 1
          : 1;
        const attemptIndex = nextAttempt - 1;

        const system = typeof lastUserMessage?.info?.system === "string" ? lastUserMessage.info.system : undefined;
        const tools = lastUserMessage?.info?.tools && typeof lastUserMessage.info.tools === "object" ? lastUserMessage.info.tools : undefined;
        const variant = typeof lastUserMessage?.info?.variant === "string" ? lastUserMessage.info.variant : undefined;

        if (nextAttempt > matchedRule.max_retries || attemptIndex >= matchedRule.backoff_ms.length) {
          attemptsBySession.set(sessionID, {
            fingerprint,
            attempts: Math.min(nextAttempt, matchedRule.max_retries),
            ruleID: matchedRule.id,
            userMessageID: retryMessageID,
          });
          handledErrorsBySession.set(sessionID, failedAssistantMessageID);

          const fallback = agentFallback;
          if (fallback) {
            const fallbackParts = current?.originalParts ?? retryParts;
            const fallbackMessageID = current?.originalMessageID ?? retryMessageID;
            log("info", `Exhausted retries for "${matchedRule.id}" — falling back to ${fallback.providerID}/${fallback.modelID} via agent "${agent ?? "unknown"}" chain`);
            await ctx.client.session.abort({
              path: { id: sessionID },
              ...(ctx.directory ? { query: { directory: ctx.directory } } : {}),
            }).catch(() => {});
            await sleep(1000);
            await ctx.client.session.promptAsync({
              path: { id: sessionID },
              ...(ctx.directory ? { query: { directory: ctx.directory } } : {}),
              body: {
                // messageID omitted — passing the original user message ID causes
                // OpenCode to append fallback text into the existing message bubble.
                ...(agent ? { agent } : {}),
                model: fallback,
                ...(system ? { system } : {}),
                ...(tools ? { tools } : {}),
                parts: fallbackParts,
              },
            });
          } else {
            const failingProviderID = model?.providerID ?? "unknown";
            log("warn", `Exhausted retries for "${matchedRule.id}" (${matchedRule.max_retries}/${matchedRule.max_retries}) — no fallback in agent "${agent ?? "unknown"}" chain for provider "${failingProviderID}"`);
            await surfaceToast(ctx, {
              title: "Retries exhausted",
              message: `Rule "${matchedRule.id}" exhausted ${matchedRule.max_retries} retries; agent "${agent ?? "unknown"}" has no fallback chain for provider "${failingProviderID}".`,
              variant: "warning",
              duration: 10000,
            });
          }
          return;
        }

        previousAttemptState = current;

        const delayMs = matchedRule.backoff_ms[attemptIndex];
        log("info", `Retry ${nextAttempt}/${matchedRule.max_retries} for "${matchedRule.id}" in ${delayMs}ms`);

        const nudgeParts = getNudgePromptParts(matchedRule, agent, attemptIndex);
        const useNudge = Boolean(nudgeParts);
        const dispatchParts = useNudge ? nudgeParts : retryParts;

        await ctx.client.session.abort({
          path: { id: sessionID },
          ...(ctx.directory ? { query: { directory: ctx.directory } } : {}),
        }).catch(() => {});
        await sleep(delayMs);

        if (useNudge) {
          log("info", `Sending nudge prompt (attempt ${nextAttempt}): "${nudgeParts[0].text.substring(0, 60)}..."`);
        }

        await ctx.client.session.promptAsync({
          path: { id: sessionID },
          ...(ctx.directory ? { query: { directory: ctx.directory } } : {}),
          body: {
            ...(!useNudge && retryMessageID ? { messageID: retryMessageID } : {}),
            ...(agent ? { agent } : {}),
            ...(model ? { model } : {}),
            ...(system ? { system } : {}),
            ...(tools ? { tools } : {}),
            ...(variant ? { variant } : {}),
            parts: dispatchParts,
          },
        });
        attemptsBySession.set(sessionID, buildAttemptState({
          tracked: current,
          fingerprint,
          retryParts,
          retryMessageID,
          attempts: nextAttempt,
          ruleID: matchedRule.id,
          nudgeParts: useNudge ? nudgeParts : undefined,
        }));
        handledErrorsBySession.set(sessionID, failedAssistantMessageID);
      } catch (dispatchError) {
        if (previousAttemptState) {
          attemptsBySession.set(sessionID, previousAttemptState);
        } else {
          attemptsBySession.delete(sessionID);
        }

        log("warn", `Failed to dispatch retry for "${matchedRule.id}": ${dispatchError?.message ?? dispatchError}`);
        await surfaceToast(ctx, {
          title: "Retry dispatch failed",
          message: `Failed to dispatch retry for rule "${matchedRule.id}": ${dispatchError?.message ?? dispatchError}`,
          variant: "error",
          duration: 10000,
        });
      } finally {
        inFlightSessions.delete(sessionID);
      }
    },
  };
};

export default ProviderConnectRetryPlugin;
