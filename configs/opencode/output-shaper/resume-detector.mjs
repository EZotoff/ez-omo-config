// configs/opencode/output-shaper/resume-detector.mjs
// Resume-after-tool-result detection for output-shaper plugin

// Returns true when the session is resuming after a tool result turn, which
// signals the shaper should dial thinking down to the resume level.
// Heuristic: one of the last 2 messages is an assistant message that contains
// at least one tool part in the "completed" state (i.e. the model just used
// a tool). We check the last 2 because at the time chat.params fires, OpenCode
// has typically already created a new empty assistant message for the current
// LLM call — so the completed tool parts live in the PREVIOUS (second-to-last)
// message. Checking the last 2 handles both timing scenarios.
// Fail-closed: any error, missing client, or missing sessionID returns false.
export async function isResumeAfterToolResult(ctx, sessionID) {
  if (!ctx?.client?.session?.messages || !sessionID) return false;
  try {
    const response = await ctx.client.session.messages({
      path: { id: sessionID },
      ...(ctx.directory ? { query: { directory: ctx.directory } } : {}),
    });
    const messages = response?.data ?? [];
    if (messages.length === 0) return false;
    // At the time chat.params fires, OpenCode has typically already created
    // a new empty assistant message for the current LLM call. The completed
    // tool parts are in the PREVIOUS message (second-to-last). Check the
    // last 2 messages to handle both timing scenarios.
    for (let i = messages.length - 1; i >= Math.max(0, messages.length - 2); i--) {
      const msg = messages[i];
      if (msg?.info?.role === "assistant") {
        const hasCompletedTool = (msg.parts ?? []).some(
          (p) => p.type === "tool" && p.state?.status === "completed"
        );
        if (hasCompletedTool) return true;
      }
    }
    return false;
  } catch {
    return false; // fail-closed: don't clamp if we can't determine
  }
}
