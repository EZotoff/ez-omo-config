// configs/opencode/aspect-dynamics/sets.mjs
// Stub set loader for aspect-dynamics plugin

const DEFAULT_SETS = [
  { id: "general", aspects: ["clarity", "conciseness", "completeness"] },
  { id: "security", aspects: ["input-validation", "secrets-handling", "injection-guard"] },
];

export async function loadSets() {
  return [...DEFAULT_SETS];
}

export function getSetById(sets, id) {
  return sets.find((s) => s.id === id);
}
