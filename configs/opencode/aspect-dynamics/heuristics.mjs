// configs/opencode/aspect-dynamics/heuristics.mjs
// Stub scorer for aspect-dynamics plugin

export function scoreAspect(aspect, context) {
  return Math.random();
}

export function shouldNudge(scores, threshold) {
  const avg = scores.length > 0
    ? scores.reduce((a, b) => a + b, 0) / scores.length
    : 0;
  return avg < threshold;
}

export function rankAspects(scoresMap) {
  return Array.from(scoresMap.entries())
    .sort((a, b) => a[1] - b[1])
    .map(([aspect]) => aspect);
}
