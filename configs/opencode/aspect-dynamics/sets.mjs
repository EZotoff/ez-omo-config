// configs/opencode/aspect-dynamics/sets.mjs
// Stub set loader for aspect-dynamics plugin

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

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

const SEED_SET_PATH = fileURLToPath(new URL("./sets/emotions-v1.json", import.meta.url));

// Test override — set by harness to inject custom sets
export const __testSetsOverride = { value: null };

function isValidAspect(aspect) {
  return (
    aspect
    && typeof aspect === "object"
    && !Array.isArray(aspect)
    && typeof aspect.id === "string"
    && aspect.id.length > 0
    && Array.isArray(aspect.heuristicPhrases)
    && aspect.heuristicPhrases.every((phrase) => typeof phrase === "string")
    && typeof aspect.nudgeInstruction === "string"
  );
}

function isValidSet(setObj) {
  return (
    setObj
    && typeof setObj === "object"
    && !Array.isArray(setObj)
    && typeof setObj.id === "string"
    && setObj.id.length > 0
    && Number.isFinite(setObj.version)
    && Number.isFinite(setObj.defaultThreshold)
    && Array.isArray(setObj.aspects)
    && setObj.aspects.every(isValidAspect)
  );
}

export async function loadSets() {
  if (__testSetsOverride.value) {
    return [...__testSetsOverride.value];
  }

  try {
    const raw = readFileSync(SEED_SET_PATH, "utf8");
    const parsed = JSON.parse(raw);
    const loaded = Array.isArray(parsed) ? parsed : [parsed];

    if (loaded.length === 0 || !loaded.every(isValidSet)) {
      console.warn(`[aspect-dynamics] Invalid set schema in ${SEED_SET_PATH}; using DEFAULT_SETS fallback`);
      return [...DEFAULT_SETS];
    }

    return loaded;
  } catch (err) {
    console.warn(`[aspect-dynamics] Failed loading sets from ${SEED_SET_PATH}: ${err.message}; using DEFAULT_SETS fallback`);
    return [...DEFAULT_SETS];
  }
}

export function getSetById(sets, id) {
  return sets.find((s) => s.id === id) ?? null;
}
