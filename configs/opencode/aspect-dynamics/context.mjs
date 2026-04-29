// configs/opencode/aspect-dynamics/context.mjs
// Stub context extractor for aspect-dynamics plugin

export async function extractContext(ctx, sessionID) {
  if (!ctx?.client?.session) {
    return null;
  }

  try {
    const response = await ctx.client.session.messages({
      path: { id: sessionID },
      ...(ctx.directory ? { query: { directory: ctx.directory } } : {}),
    });

    const messages = Array.isArray(response?.data) ? response.data : [];

    return {
      messageCount: messages.length,
      lastUserMessage: messages[messages.length - 1] ?? null,
      messages,
    };
  } catch {
    return null;
  }
}

export function getEventSessionID(event) {
  const props = event?.properties ?? {};
  return props.sessionID ?? props.info?.sessionID;
}
