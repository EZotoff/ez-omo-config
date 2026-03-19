import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const REGISTRY_PATH = path.join(os.homedir(), ".config", "opencode", "retry-errors.json");

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

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
        console.warn(`[retry-plugin] Skipping invalid registry rule "${entry?.id ?? "unknown"}": ${error?.message ?? error}`);
        return [];
      }
    });
  } catch (error) {
    console.warn(`[retry-plugin] Failed to load registry: ${error?.message ?? error}`);
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

export const ProviderConnectRetryPlugin = async (ctx) => {
  const attemptsBySession = new Map();
  const inFlightSessions = new Set();
  const handledErrorsBySession = new Map();

  return {
    event: async ({ event }) => {
      const sessionID = getEventSessionID(event);
      if (!sessionID) return;

      if (event?.type === "session.idle") {
        if (!inFlightSessions.has(sessionID)) {
          clearSessionState(sessionID, attemptsBySession, handledErrorsBySession);
        }
        return;
      }

      if (event?.type === "message.updated") {
        const info = event.properties?.info ?? {};

        if (info.role === "assistant" && !info.error) {
          return;
        }

        if (info.role === "user") {
          const currentParts = sanitizePromptParts(event.properties?.parts ?? info.parts);
          if (currentParts.length > 0) {
            const nextFingerprint = fingerprintParts(currentParts);
            const nextMessageID = typeof info.id === "string" && info.id.length > 0 ? info.id : undefined;
            const existing = attemptsBySession.get(sessionID);
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
      console.info(`[retry-plugin] Error matched rule "${matchedRule.id}": ${errorMessage.substring(0, 100)}`);
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
        if (typeof parentID === "string" && parentID.length > 0) {
          console.info(`[retry-plugin] Skipping retry for child session ${sessionID}`);
          return;
        }

        const messagesResponse = await ctx.client.session.messages({
          path: { id: sessionID },
          ...(ctx.directory ? { query: { directory: ctx.directory } } : {}),
        }).catch(() => null);

        const messages = Array.isArray(messagesResponse?.data) ? messagesResponse.data : [];
        const failedAssistantMessageID = getFailedAssistantMessageID(event, messages);
        if (!failedAssistantMessageID) {
          console.warn(`[retry-plugin] Skipping retry for "${matchedRule.id}" — no failed assistant message ID available`);
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
          console.warn(`[retry-plugin] Skipping retry for "${matchedRule.id}" — tool execution detected in session`);
          return;
        }

        const fingerprint = fingerprintParts(retryParts);
        const current = attemptsBySession.get(sessionID);
        const nextAttempt = current
          && current.fingerprint === fingerprint
          && current.ruleID === matchedRule.id
          && current.userMessageID === retryMessageID
          ? current.attempts + 1
          : 1;
        const attemptIndex = nextAttempt - 1;
        if (nextAttempt > matchedRule.max_retries || attemptIndex >= matchedRule.backoff_ms.length) {
          attemptsBySession.set(sessionID, {
            fingerprint,
            attempts: Math.min(nextAttempt, matchedRule.max_retries),
            ruleID: matchedRule.id,
            userMessageID: retryMessageID,
          });
          handledErrorsBySession.set(sessionID, failedAssistantMessageID);
          console.warn(`[retry-plugin] Exhausted retries for "${matchedRule.id}" (${matchedRule.max_retries}/${matchedRule.max_retries})`);
          return;
        }

        previousAttemptState = current;
        const nextAttemptState = {
          fingerprint,
          attempts: nextAttempt,
          ruleID: matchedRule.id,
          userMessageID: retryMessageID,
        };

        const delayMs = matchedRule.backoff_ms[attemptIndex];
        console.info(`[retry-plugin] Retry ${nextAttempt}/${matchedRule.max_retries} for "${matchedRule.id}" in ${delayMs}ms`);
        const agent = getEventAgent(event, messages) ?? lastUserMessage?.info?.agent;
        const model = getEventModel(event, messages) ?? lastUserMessage?.info?.model;
        const system = typeof lastUserMessage?.info?.system === "string" ? lastUserMessage.info.system : undefined;
        const tools = lastUserMessage?.info?.tools && typeof lastUserMessage.info.tools === "object" ? lastUserMessage.info.tools : undefined;
        const variant = typeof lastUserMessage?.info?.variant === "string" ? lastUserMessage.info.variant : undefined;

        await ctx.client.session.abort({
          path: { id: sessionID },
          ...(ctx.directory ? { query: { directory: ctx.directory } } : {}),
        }).catch(() => {});
        await sleep(delayMs);
        await ctx.client.session.promptAsync({
          path: { id: sessionID },
          ...(ctx.directory ? { query: { directory: ctx.directory } } : {}),
          body: {
            ...(retryMessageID ? { messageID: retryMessageID } : {}),
            ...(agent ? { agent } : {}),
            ...(model ? { model } : {}),
            ...(system ? { system } : {}),
            ...(tools ? { tools } : {}),
            ...(variant ? { variant } : {}),
            parts: retryParts,
          },
        });
        attemptsBySession.set(sessionID, nextAttemptState);
        handledErrorsBySession.set(sessionID, failedAssistantMessageID);
      } catch (dispatchError) {
        if (previousAttemptState) {
          attemptsBySession.set(sessionID, previousAttemptState);
        } else {
          attemptsBySession.delete(sessionID);
        }

        console.warn(`[retry-plugin] Failed to dispatch retry for "${matchedRule.id}": ${dispatchError?.message ?? dispatchError}`);
      } finally {
        inFlightSessions.delete(sessionID);
      }
    },
  };
};

export default ProviderConnectRetryPlugin;
