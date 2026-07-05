// Assembles the game-content payload served at GET /content. The Roblox
// server fetches this once at boot so design data has a single source of
// truth (the content/ JSON files); the Luau mirrors become fallbacks.
//
// Content is static per-process — it ships with the deploy — so the payload
// and its version hash are computed once. `version` changes exactly when a
// deploy changes content, letting the game log/compare what it's running on.
// Future content kinds (enemies, nodes, stores, quests) join this payload.

import crypto from "node:crypto";
import { ITEMS, STARTER_ITEMS, GRID, EQUIPMENT_SLOTS } from "./items.js";
import { STORES } from "./stores.js";

const payload = {
  items: ITEMS,
  starterItems: STARTER_ITEMS,
  grid: GRID,
  equipmentSlots: EQUIPMENT_SLOTS,
  stores: STORES,
};

const version = crypto
  .createHash("sha256")
  .update(JSON.stringify(payload))
  .digest("hex")
  .slice(0, 12);

export const content = { version, ...payload };
