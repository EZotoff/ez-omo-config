// configs/opencode/output-shaper/resume-detector.mjs
// Resume-after-tool-result detection for output-shaper plugin

// Returns true when the session is resuming after a tool result turn, which
// signals the shaper should dial thinking down to the resume level.
// Heuristic: the last message is an assistant message that contains at least
// one tool part in the "completed" state (i.e. the model just used a tool).
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
    const last = messages[messages.length - 1];
    // Resume turn: last message is assistant with completed tool parts
    if (last?.info?.role === "assistant") {
      return (last.parts ?? []).some(
        (p) => p.type === "tool" && p.state?.status === "completed"
      );
    }
    // New question: last message is user
    return false;
  } catch {
    return false; // fail-closed: don't clamp if we can't determine
  }
}
