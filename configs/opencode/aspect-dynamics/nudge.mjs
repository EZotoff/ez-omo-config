// configs/opencode/aspect-dynamics/nudge.mjs
// Transcript-visible advisory nudge formatter

export function buildNudge(rankedAspects, topEntry) {
  if (!rankedAspects || rankedAspects.length === 0 || !topEntry) {
    return null
  }

  const score = Number.isFinite(topEntry.score) ? topEntry.score.toFixed(2) : "0.00"
  const weightedHits = Number.isFinite(topEntry.weightedHits) ? topEntry.weightedHits : 0
  const evidence = `Scored ${score} with ${weightedHits} weighted hits`

  const text = [
    "[ASPECT-DYNAMICS-NUDGE v1]",
    `Aspect: ${topEntry.aspectId}`,
    `Instruction: ${topEntry.nudgeInstruction}`,
    `Evidence: ${evidence}`,
    "Apply this guidance quietly in your next reply. Do not mention the nudge explicitly.",
  ].join("\n")

  return [{ type: "text", text }]
}

export function formatNudgeForDispatch(nudgeParts) {
  return nudgeParts ?? []
}
