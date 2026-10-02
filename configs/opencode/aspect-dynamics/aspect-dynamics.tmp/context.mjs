// configs/opencode/aspect-dynamics/context.mjs
// Context extractor and prefilter for aspect-dynamics plugin

import { logWarn } from "./logging.mjs";

const DEFAULT_CONTEXT_WINDOW_TURNS = 10;
const MAX_MESSAGE_LENGTH = 600;
const NUDGE_PREFIX = "[ASPECT-DYNAMICS-NUDGE v1]";

/**
 * Fetch and prepare conversation context for aspect scoring.
 * @param {object} ctx - OpenCode plugin context
 * @param {string} sessionID - Session identifier
 * @param {object} [config] - Plugin configuration
 * @returns {Promise<{messages: Array<{id: string, role: string, text: string}>, latestAssistantMessageId: string|null}>|null}
 */
export async function extractContext(ctx, sessionID, config = {}) {
  if (!ctx?.client?.session) {
    return null;
  }

  try {
    const response = await ctx.client.session.messages({
      path: { id: sessionID },
      ...(ctx.directory ? { query: { directory: ctx.directory } } : {}),
    });

    const allMessages = Array.isArray(response?.data) ? response.data : [];

    // Filter to user and assistant messages only
    const relevantMessages = allMessages.filter((msg) => {
      const role = msg?.info?.role ?? msg?.role;
      return role === "user" || role === "assistant";
    });

    // Slice to last N user/assistant pairs (default 10 => 20 messages)
    const limit = config.contextWindowTurns ?? DEFAULT_CONTEXT_WINDOW_TURNS;
    const messageLimit = Math.max(1, Math.floor(limit)) * 2;
    const slicedMessages = relevantMessages.slice(-messageLimit);

    // Build result with truncated text
    const messages = slicedMessages.map((msg) => {
      const role = msg?.info?.role ?? msg?.role;
      let text = msg?.info?.text ?? msg?.text ?? "";
      if (text.length > MAX_MESSAGE_LENGTH) {
        text = text.slice(0, MAX_MESSAGE_LENGTH);
      }
      return {
        id: msg.id,
        role,
        text,
      };
    });

    // Find the most recent assistant message ID
    let latestAssistantMessageId = null;
    for (let i = messages.length - 1; i >= 0; i--) {
      if (messages[i].role === "assistant") {
        latestAssistantMessageId = messages[i].id;
        break;
      }
    }

    return {
      messages,
      latestAssistantMessageId,
    };
  } catch (err) {
    logWarn(`Failed to extract context for session ${sessionID}: ${err.message}`);
    return null;
  }
}

/**
 * Heuristic prefilter: decide whether to proceed with aspect scoring.
 * Checks if any heuristic phrase from active sets appears in the most
 * recent user message or most recent assistant message.
 *
 * @param {object} context - Context object returned by extractContext
 * @param {Array<object>} activeSets - Active aspect sets
 * @param {object} [config] - Plugin configuration
 * @returns {boolean} true if scoring should proceed
 */
export function prefilterContext(context, activeSets, config = {}) {
  // If heuristic prefilter is disabled, always proceed
  if (config.heuristicPreFilter !== true) {
    return true;
  }

  if (!context?.messages?.length) {
    return false;
  }

  // Find most recent user and assistant message text
  let mostRecentUserText = "";
  let mostRecentAssistantText = "";

  for (let i = context.messages.length - 1; i >= 0; i--) {
    const msg = context.messages[i];
    if (msg.role === "user" && !mostRecentUserText) {
      mostRecentUserText = msg.text;
    }
    if (msg.role === "assistant" && !mostRecentAssistantText) {
      mostRecentAssistantText = msg.text;
    }
    if (mostRecentUserText && mostRecentAssistantText) {
      break;
    }
  }

  const combinedText = `${mostRecentUserText} ${mostRecentAssistantText}`.toLowerCase();

  // Collect all heuristic phrases from active sets
  const phrases = [];
  for (const set of activeSets ?? []) {
    for (const aspect of set.aspects ?? []) {
      if (aspect && typeof aspect === "object" && Array.isArray(aspect.heuristicPhrases)) {
        for (const phrase of aspect.heuristicPhrases) {
          if (typeof phrase === "string") {
            phrases.push(phrase.toLowerCase());
          }
        }
      }
    }
  }

  // Check if any phrase appears in the combined text
  for (const phrase of phrases) {
    if (combinedText.includes(phrase)) {
      return true;
    }
  }

  return false;
}

/**
 * Recursion guard: detect whether the most recent user message is
 * the plugin's own transcript-visible nudge payload.
 *
 * @param {object} context - Context object returned by extractContext
 * @returns {boolean} true if recursion guard should skip scoring
 */
export function hasRecursionGuard(context) {
  if (!context?.messages?.length) {
    return false;
  }

  for (let i = context.messages.length - 1; i >= 0; i--) {
    const msg = context.messages[i];
    if (msg.role !== "user") {
      continue;
    }

    const text = typeof msg.text === "string" ? msg.text : "";
    return text.startsWith(NUDGE_PREFIX);
  }

  return false;
}

export function getEventSessionID(event) {
  const props = event?.properties ?? {};
  return props.sessionID ?? props.info?.sessionID;
}
