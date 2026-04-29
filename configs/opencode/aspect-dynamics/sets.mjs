// configs/opencode/aspect-dynamics/sets.mjs
// Stub set loader for aspect-dynamics plugin

const DEFAULT_SETS = [
  { id: "general", aspects: ["clarity", "conciseness", "completeness"] },
  { id: "security", aspects: ["input-validation", "secrets-handling", "injection-guard"] },
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
