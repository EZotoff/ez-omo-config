// configs/opencode/aspect-dynamics/sets.mjs
// Versioned seed set loader — discovers and validates all JSON set files
// under ./sets/, and exposes selection helpers that honor configured activeSets.

import { readdirSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { extname, join } from "node:path";

const __dirname = fileURLToPath(new URL(".", import.meta.url));
const SETS_DIR = join(__dirname, "sets");

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

/**
 * Load all valid JSON seed set files from the sets/ directory.
 * Skips invalid files with a warning. Returns sets in deterministic
 * (alphabetical-by-filename) order.
 */
export async function loadSets() {
  if (__testSetsOverride.value) {
    return [...__testSetsOverride.value];
  }

  const loaded = [];

  let filenames;
  try {
    filenames = readdirSync(SETS_DIR);
  } catch (err) {
    console.warn(`[aspect-dynamics] Failed to read sets directory ${SETS_DIR}: ${err.message}; returning empty set list`);
    return [];
  }

  // Sort deterministically by filename
  const jsonFiles = filenames
    .filter((f) => extname(f).toLowerCase() === ".json")
    .sort();

  for (const filename of jsonFiles) {
    const filePath = join(SETS_DIR, filename);
    try {
      const raw = readFileSync(filePath, "utf8");
      const parsed = JSON.parse(raw);
      const entries = Array.isArray(parsed) ? parsed : [parsed];

      for (const entry of entries) {
        if (isValidSet(entry)) {
          loaded.push(entry);
        } else {
          console.warn(`[aspect-dynamics] Skipping invalid set entry in ${filename}`);
        }
      }
    } catch (err) {
      console.warn(`[aspect-dynamics] Failed to load ${filename}: ${err.message}; skipping`);
    }
  }

  return loaded;
}

/**
 * Filter and order sets according to a configured activeSetIds array.
 * Returns sets in the exact order specified by activeSetIds.
 *
 * If activeSetIds is null/undefined/empty, returns all loaded sets
 * (backward-compatible default behavior).
 *
 * If any ID in activeSetIds is not found among loaded sets, emits a
 * warning and returns an empty array (fail-closed).
 *
 * @param {Array} sets — all loaded seed sets
 * @param {Array|undefined} activeSetIds — ordered IDs to select; undefined = all
 * @returns {Array} filtered set array
 */
export function selectActiveSets(sets, activeSetIds) {
  if (!activeSetIds || !Array.isArray(activeSetIds) || activeSetIds.length === 0) {
    return sets;
  }

  const result = [];
  for (const id of activeSetIds) {
    const set = sets.find((s) => s.id === id);
    if (!set) {
      console.warn(`[aspect-dynamics] Unknown active set ID: ${id}`);
      return [];
    }
    result.push(set);
  }
  return result;
}

export function getSetById(sets, id) {
  return sets.find((s) => s.id === id) ?? null;
}
