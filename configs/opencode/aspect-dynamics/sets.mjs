// configs/opencode/aspect-dynamics/sets.mjs
// Stub set loader for aspect-dynamics plugin

const DEFAULT_SETS = [
  {
    id: "general",
    version: 1,
    defaultThreshold: 0.75,
    aspects: [
      { id: "clarity", heuristicPhrases: ["unclear", "confusing"], nudgeInstruction: "Be clearer." },
      { id: "conciseness", heuristicPhrases: ["too long", "verbose"], nudgeInstruction: "Be more concise." },
    ],
  },
];

// Test override — set by harness to inject custom sets
export const __testSetsOverride = { value: null };

export async function loadSets() {
  if (__testSetsOverride.value) {
    return [...__testSetsOverride.value];
  }
  return [...DEFAULT_SETS];
}

export function getSetById(sets, id) {
  return sets.find((s) => s.id === id);
}
