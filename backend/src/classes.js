// Class ids, mirrored from roblox/src/shared/Classes.lua. The backend only
// needs to know which ids are valid and what a fresh class-levels blob looks
// like — the passive stat multipliers themselves are Roblox-only.

export const CLASS_IDS = ["knight", "archer", "mage", "cleric"];

export const DEFAULT_CLASS = "knight";

export function isValidClass(id) {
  return CLASS_IDS.includes(id);
}

// A brand-new player's class_levels: every class starts at level 1 / 0 xp.
export function defaultClassLevels() {
  const levels = {};
  for (const id of CLASS_IDS) {
    levels[id] = { level: 1, xp: 0 };
  }
  return levels;
}
