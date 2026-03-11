const CONNECT_ERROR_FRAGMENT = "unable to connect. is the computer able to access the url?";
const MAX_RETRIES = 3;
const INITIAL_DELAY_MS = 2000;
const MAX_DELAY_MS = 8000;

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

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

      if (event?.type === "message.updated") {
        const info = event.properties?.info ?? {};

        if (info.role === "assistant" && !info.error) {
          clearSessionState(sessionID, attemptsBySession, handledErrorsBySession);
          return;
        }

        if (info.role === "user") {
          const currentParts = sanitizePromptParts(event.properties?.parts ?? info.parts);
          if (currentParts.length > 0) {
            const nextFingerprint = fingerprintParts(currentParts);
            const existing = attemptsBySession.get(sessionID);
            if (!existing || existing.fingerprint !== nextFingerprint) {
              attemptsBySession.set(sessionID, { fingerprint: nextFingerprint, attempts: 0 });
              handledErrorsBySession.delete(sessionID);
            }
          }
          return;
        }
      }

      if (event?.type !== "session.error" && event?.type !== "message.updated") return;

      const error = getEventError(event);
      const errorMessage = getErrorMessage(error);
      if (!errorMessage.includes(CONNECT_ERROR_FRAGMENT)) return;
      if (inFlightSessions.has(sessionID)) return;

      const messagesResponse = await ctx.client.session.messages({
        sessionID,
        directory: ctx.directory,
      }).catch(() => null);

      const messages = Array.isArray(messagesResponse?.data) ? messagesResponse.data : [];
      const failedAssistantMessageID = getFailedAssistantMessageID(event, messages) ?? `${errorMessage}:${messages.length}`;
      if (handledErrorsBySession.get(sessionID) === failedAssistantMessageID) return;

      const lastUserMessage = [...messages].reverse().find((message) => message?.info?.role === "user");
      const retryParts = sanitizePromptParts(lastUserMessage?.parts ?? lastUserMessage?.info?.parts);
      if (retryParts.length === 0) return;
      const retryMessageID = typeof lastUserMessage?.info?.id === "string" && lastUserMessage.info.id.length > 0
        ? lastUserMessage.info.id
        : undefined;

      const fingerprint = fingerprintParts(retryParts);
      const current = attemptsBySession.get(sessionID);
      const nextAttempt = current && current.fingerprint === fingerprint ? current.attempts + 1 : 1;
      if (nextAttempt > MAX_RETRIES) return;

      attemptsBySession.set(sessionID, { fingerprint, attempts: nextAttempt });
      handledErrorsBySession.set(sessionID, failedAssistantMessageID);
      inFlightSessions.add(sessionID);

      const delayMs = Math.min(INITIAL_DELAY_MS * 2 ** (nextAttempt - 1), MAX_DELAY_MS);
      const agent = getEventAgent(event, messages) ?? lastUserMessage?.info?.agent;
      const model = getEventModel(event, messages) ?? lastUserMessage?.info?.model;
      const system = typeof lastUserMessage?.info?.system === "string" ? lastUserMessage.info.system : undefined;
      const tools = lastUserMessage?.info?.tools && typeof lastUserMessage.info.tools === "object" ? lastUserMessage.info.tools : undefined;
      const variant = typeof lastUserMessage?.info?.variant === "string" ? lastUserMessage.info.variant : undefined;

      try {
        await ctx.client.session.abort({
          sessionID,
          directory: ctx.directory,
        }).catch(() => {});
        await sleep(delayMs);
        await ctx.client.session.promptAsync({
          sessionID,
          directory: ctx.directory,
          ...(retryMessageID ? { messageID: retryMessageID } : {}),
          ...(agent ? { agent } : {}),
          ...(model ? { model } : {}),
          ...(system ? { system } : {}),
          ...(tools ? { tools } : {}),
          ...(variant ? { variant } : {}),
          parts: retryParts,
        });
      } finally {
        inFlightSessions.delete(sessionID);
      }
    },
  };
};

export default ProviderConnectRetryPlugin;
