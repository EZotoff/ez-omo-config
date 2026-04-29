// configs/opencode/aspect-dynamics/nudge.mjs
// Stub nudge builder for aspect-dynamics plugin

export function buildNudge(rankedAspects) {
  if (!rankedAspects || rankedAspects.length === 0) {
    return null;
  }

  const text = `Consider improving: ${rankedAspects.slice(0, 3).join(", ")}`;
  return [{ type: "text", text }];
}

export function formatNudgeForDispatch(nudgeParts) {
  return nudgeParts ?? [];
}
