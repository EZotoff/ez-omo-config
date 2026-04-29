// configs/opencode/aspect-dynamics/heuristics.mjs
// Deterministic heuristic scorer for aspect-dynamics plugin

/**
 * Score all aspects from active sets against the conversation context.
 * @param {object} context - { messages: [{id, role, text}], latestAssistantMessageId }
 * @param {Array<object>} activeSets - Loaded aspect sets
 * @returns {object} { topAspectId, topScore, evidenceSummary, allScores }
 */
export function scoreAspects(context, activeSets) {
  const allScores = new Map();
  let topAspectId = null;
  let topScore = -1;
  let evidenceSummary = "";

  for (const set of activeSets) {
    for (const aspect of set.aspects) {
      const weightedHits = calculateAspectScore(aspect, context);
      const normalizedScore = Math.min(1, weightedHits / 2);
      
      const key = `${set.id}:${aspect.id}`;
      allScores.set(key, {
        aspectId: aspect.id,
        setId: set.id,
        score: normalizedScore,
        weightedHits,
        nudgeInstruction: aspect.nudgeInstruction,
      });

      if (normalizedScore > topScore) {
        topScore = normalizedScore;
        topAspectId = key;
        evidenceSummary = `Aspect "${aspect.id}" scored ${normalizedScore.toFixed(2)} with ${weightedHits} weighted hits`;
      } else if (normalizedScore === topScore && topAspectId) {
        const currentTop = allScores.get(topAspectId);
        const currentTopSet = activeSets.find((s) => s.id === currentTop.setId);
        const currentTopAspectObj = currentTopSet?.aspects.find((a) => a.id === currentTop.aspectId);
        const tieBreak = resolveTie(aspect, currentTopAspectObj, context, currentTopSet?.aspects ?? []);
        if (tieBreak === aspect.id) {
          topAspectId = key;
          evidenceSummary = `Aspect "${aspect.id}" scored ${normalizedScore.toFixed(2)} (tie-break winner)`;
        }
      }
    }
  }

  return {
    topAspectId,
    topScore: topScore === -1 ? 0 : topScore,
    evidenceSummary,
    allScores,
  };
}

/**
 * Calculate weighted hit count for a single aspect against context messages.
 * @returns {number} weighted hit count (not normalized)
 */
function calculateAspectScore(aspect, context) {
  if (!context?.messages?.length || !aspect?.heuristicPhrases?.length) {
    return 0;
  }

  let weightedHits = 0;
  let mostRecentUserIndex = -1;
  let mostRecentAssistantIndex = -1;

  // Find most recent user and assistant message indices
  for (let i = context.messages.length - 1; i >= 0; i--) {
    if (mostRecentUserIndex === -1 && context.messages[i].role === "user") {
      mostRecentUserIndex = i;
    }
    if (mostRecentAssistantIndex === -1 && context.messages[i].role === "assistant") {
      mostRecentAssistantIndex = i;
    }
    if (mostRecentUserIndex !== -1 && mostRecentAssistantIndex !== -1) break;
  }

  for (let i = 0; i < context.messages.length; i++) {
    const msg = context.messages[i];
    if (msg.role !== "user" && msg.role !== "assistant") continue;

    const text = (msg.text || "").toLowerCase();
    let hitCount = 0;

    for (const phrase of aspect.heuristicPhrases) {
      if (text.includes(phrase.toLowerCase())) {
        hitCount++;
      }
    }

    if (hitCount > 0) {
      let weight;
      if (msg.role === "user" && i === mostRecentUserIndex) {
        weight = 1.0;
      } else if (msg.role === "assistant" && i === mostRecentAssistantIndex) {
        weight = 0.5;
      } else {
        weight = 0.25;
      }
      weightedHits += hitCount * weight;
    }
  }

  return weightedHits;
}

/**
 * Determine if a nudge should be dispatched based on top score and threshold.
 * @param {number} topScore - The highest aspect score
 * @param {number} threshold - Threshold to cross (default 0.75)
 * @returns {boolean}
 */
export function shouldNudge(topScore, threshold = 0.75) {
  return topScore >= threshold;
}

/**
 * Rank aspects by score descending.
 * @param {Map} allScores - Map of aspect entries
 * @returns {Array<string>} Aspect IDs sorted by score descending
 */
export function rankAspects(allScores) {
  return Array.from(allScores.values())
    .sort((a, b) => b.score - a.score)
    .map((entry) => entry.aspectId);
}

/**
 * Resolve ties between two aspects.
 * First: higher most-recent-user hit count wins.
 * Second: aspect order in set file wins (lower index = higher priority).
 * Final: stable lexical fallback.
 * @returns {string} The winning aspect ID
 */
function resolveTie(aspectA, aspectB, context, aspectList) {
  if (!aspectA) {
    return aspectB?.id;
  }
  if (!aspectB) {
    return aspectA.id;
  }

  // Count hits in most recent user message
  const userHitsA = countHitsInMostRecentUser(aspectA, context);
  const userHitsB = countHitsInMostRecentUser(aspectB, context);

  if (userHitsA !== userHitsB) {
    return userHitsA > userHitsB ? aspectA.id : aspectB.id;
  }

  // Tie-break by aspect order in set file
  const indexA = aspectList.findIndex(a => a.id === aspectA.id);
  const indexB = aspectList.findIndex(a => a.id === aspectB.id);
  if (indexA !== indexB) {
    return indexA < indexB ? aspectA.id : aspectB.id;
  }

  // Final fallback: lexical
  return aspectA.id.localeCompare(aspectB.id) <= 0 ? aspectA.id : aspectB.id;
}

function countHitsInMostRecentUser(aspect, context) {
  if (!context?.messages?.length || !aspect?.heuristicPhrases?.length) return 0;

  for (let i = context.messages.length - 1; i >= 0; i--) {
    if (context.messages[i].role === "user") {
      const text = (context.messages[i].text || "").toLowerCase();
      let count = 0;
      for (const phrase of aspect.heuristicPhrases) {
        if (text.includes(phrase.toLowerCase())) count++;
      }
      return count;
    }
  }
  return 0;
}
