// Item definitions, loaded from the git-tracked content file
// (content/items.json) — the source of truth for item/starter-kit design
// data. Mirrored in the Roblox code (shared/Items.lua) for now; the game
// fetches GET /content at boot so the mirror is only a fallback.
//
// `size` is the grid footprint [width, height] in inventory cells.
// Armor carries a `slot` naming the paper-doll slot it fits.
// Weapons/tools carry `reach` (studs a swing/gather/focus can connect),
// ranged weapons a `manaCost` per cast.
//
// Validation below fails the boot loudly on malformed content — better a
// dead deploy than a live server handing out broken defs.

import fs from "node:fs";

const raw = JSON.parse(
  fs.readFileSync(new URL("../content/items.json", import.meta.url), "utf8")
);

const ARMOR_SLOTS = new Set(["head", "chest", "hands", "legs", "feet"]);

// Optional def-level rarity (absent = common). Mirrors shared/Rarity.lua;
// rolled-instance rarity is validated separately in inventory.js.
const RARITIES = new Set(["common", "uncommon", "rare", "epic", "legendary"]);

function fail(message) {
  throw new Error(`content/items.json: ${message}`);
}

function validateItem(key, def) {
  if (def.id !== key) fail(`item "${key}" has mismatched id "${def.id}"`);
  if (typeof def.name !== "string" || !def.name) fail(`item "${key}" needs a name`);
  if (typeof def.type !== "string" || !def.type) fail(`item "${key}" needs a type`);
  const size = def.size;
  if (
    !Array.isArray(size) ||
    size.length !== 2 ||
    !size.every((n) => Number.isInteger(n) && n > 0)
  ) {
    fail(`item "${key}" needs a size [w, h] of positive integers`);
  }
  if (typeof def.stackable !== "boolean") fail(`item "${key}" needs stackable`);
  if (!Number.isInteger(def.maxStack) || def.maxStack < 1) {
    fail(`item "${key}" needs a positive integer maxStack`);
  }
  if (def.type === "armor" && !ARMOR_SLOTS.has(def.slot)) {
    fail(`armor "${key}" needs a slot in ${[...ARMOR_SLOTS].join("/")}`);
  }
  if (def.rarity !== undefined && !RARITIES.has(def.rarity)) {
    fail(`item "${key}" has unknown rarity "${def.rarity}"`);
  }
}

for (const [key, def] of Object.entries(raw.items)) validateItem(key, def);
for (const entry of raw.starterItems) {
  if (!raw.items[entry.itemId]) fail(`starter item "${entry.itemId}" is not defined`);
  if (!Number.isInteger(entry.quantity) || entry.quantity < 1) {
    fail(`starter item "${entry.itemId}" needs a positive integer quantity`);
  }
}

export const ITEMS = raw.items;

// Items a brand-new player starts with.
export const STARTER_ITEMS = raw.starterItems;

// The permanent starter kit (tools/weapons). Each id is granted ONCE per
// player (recorded in players.granted_starter_items) — newly-added starter
// gear reaches existing players on their next load, but dropped/sold gear
// stays gone. See ensureStarterEquippables in playerService.js.
export const STARTER_EQUIPPABLES = STARTER_ITEMS.filter((entry) => {
  const def = ITEMS[entry.itemId];
  return def && (def.type === "weapon" || def.type === "tool");
});

// The main inventory grid: fixed width, rows grow with backpack tiers
// later. Mirrored in Roblox shared/Config.lua. Structural, not content —
// stored stack positions assume these dims, so it lives in code.
export const GRID = { width: 10, height: 30 };

// Paper-doll equipment slots. A slot's index is its `x` in the `equipment`
// container (y = 0) — the order below is persisted data, never reorder.
// Mirrored in Roblox shared/Items.lua.
export const EQUIPMENT_SLOTS = [
  "weapon",
  "offhand",
  "head",
  "chest",
  "hands",
  "legs",
  "feet",
  "back",
  "ring1",
  "ring2",
];

// Whether an item def may sit in the given equipment slot.
export function slotAccepts(slotName, def) {
  if (!def) return false;
  if (slotName === "weapon" || slotName === "offhand") {
    return def.type === "weapon" || def.type === "tool" || def.type === "placeable";
  }
  if (slotName === "ring1" || slotName === "ring2") return def.type === "ring";
  if (slotName === "back") return def.type === "backpack";
  return def.type === "armor" && def.slot === slotName;
}

export function getItem(itemId) {
  return ITEMS[itemId] || null;
}

export function maxStackFor(itemId) {
  const item = ITEMS[itemId];
  if (!item) return 0;
  return item.stackable ? item.maxStack : 1;
}

// Footprint [w, h] of an item as placed (swapped when rotated).
export function sizeFor(itemId, rotated) {
  const item = ITEMS[itemId];
  const [w, h] = (item && item.size) || [1, 1];
  return rotated ? [h, w] : [w, h];
}
