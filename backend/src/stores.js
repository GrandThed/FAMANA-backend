// Store definitions (vendor trade lists), loaded from the git-tracked
// content file (content/stores.json). Prices are gold per unit; an entry
// may be buy-only (no sellPrice), sell-only (no buyPrice), or both.
// Vendor NPC placement lives Roblox-side (VendorService VENDOR_DEFS) —
// the backend owns the economy data, the game owns the world layout.
//
// Like items.js, validation fails the boot loudly on malformed content.

import fs from "node:fs";
import { ITEMS } from "./items.js";

const raw = JSON.parse(
  fs.readFileSync(new URL("../content/stores.json", import.meta.url), "utf8")
);

function fail(message) {
  throw new Error(`content/stores.json: ${message}`);
}

function validatePrice(where, value) {
  if (value !== undefined && (!Number.isInteger(value) || value < 1)) {
    fail(`${where} must be a positive integer`);
  }
}

for (const [key, store] of Object.entries(raw.stores)) {
  if (store.id !== key) fail(`store "${key}" has mismatched id "${store.id}"`);
  if (typeof store.name !== "string" || !store.name) fail(`store "${key}" needs a name`);
  if (!Array.isArray(store.trades) || store.trades.length === 0) {
    fail(`store "${key}" needs a non-empty trades list`);
  }
  const seen = new Set();
  for (const trade of store.trades) {
    const where = `store "${key}" trade "${trade.itemId}"`;
    if (!ITEMS[trade.itemId]) fail(`${where} references an unknown item`);
    if (seen.has(trade.itemId)) fail(`${where} is listed twice`);
    seen.add(trade.itemId);
    validatePrice(`${where} buyPrice`, trade.buyPrice);
    validatePrice(`${where} sellPrice`, trade.sellPrice);
    if (trade.buyPrice === undefined && trade.sellPrice === undefined) {
      fail(`${where} needs a buyPrice and/or sellPrice`);
    }
  }
}

export const STORES = raw.stores;
