// Grid inventory mutation logic. All operations run inside a
// transaction so concurrent server hops can't lose or duplicate items.
//
// Layout model: every row is an item stack placed at (x, y) in a container.
//   * 'main'      — the GRID.width x GRID.height backpack grid; items occupy
//                   a WxH footprint (item def `size`, swapped when `rotated`).
//   * 'equipment' — the paper doll; x = EQUIPMENT_SLOTS index, y = 0, one
//                   item per slot (footprints don't apply).
// Legacy pre-grid rows (x IS NULL) are repacked into grid positions the
// first time any operation touches the inventory.
//
// Rolled (unique) items carry `meta` ({ itemLevel, rarity?, traits }) per row. Meta
// rows are item INSTANCES: they never merge/top-up, generic removeItem skips
// them, and sortInventory re-places them as their own stacks.

import {
  getItem,
  maxStackFor,
  sizeFor,
  slotAccepts,
  GRID,
  EQUIPMENT_SLOTS,
} from "./items.js";

const err = (message, code, extra = {}) =>
  Object.assign(new Error(message), { code, ...extra });

// 2026-07 English rename (game language decision): item ids and trait/school
// ids persisted before the rename translate at READ time — every write path
// below then stores the new ids, so rows converge to English as they're
// touched (sortInventory rewrites them wholesale). Spell ids in hotbar binds
// are translated client-side by HotbarBinds on load.
const LEGACY_IDS = {
  emblem_sacerdote: "emblem_light_priest",
  emblem_vengador: "emblem_holy_avenger",
  emblem_oraculo: "emblem_oracle",
  sacerdote_luz: "light_priest",
  vengador_sagrado: "holy_avenger",
  oraculo: "oracle",
};

function translateLegacyRow(row) {
  if (LEGACY_IDS[row.itemId]) row.itemId = LEGACY_IDS[row.itemId];
  const traits = row.meta && row.meta.traits;
  if (traits) {
    for (const [traitId, points] of Object.entries(traits)) {
      if (LEGACY_IDS[traitId]) {
        delete traits[traitId];
        traits[LEGACY_IDS[traitId]] = points;
      }
    }
  }
  return row;
}

async function fetchRows(client, playerId) {
  const { rows } = await client.query(
    `SELECT id, slot_index AS "slotIndex", container_id AS "containerId",
            x, y, rotated, item_id AS "itemId", quantity, meta
       FROM inventory_items
      WHERE player_id = $1
      ORDER BY container_id, y NULLS LAST, x NULLS LAST, id`,
    [playerId]
  );
  return rows.map(translateLegacyRow);
}

// Rarity tiers a rolled instance may carry (mirrors Roblox shared/Rarity.lua
// and the def-level validation in items.js).
export const RARITIES = new Set(["common", "uncommon", "rare", "epic", "legendary"]);

// Shape-validates client-provided instance meta (trait-id VALIDITY lives in
// the Roblox shared Traits module; unknown ids simply aggregate to nothing).
// Returns a clean object or null.
export function sanitizeMeta(meta) {
  if (!meta || typeof meta !== "object" || Array.isArray(meta)) return null;
  const out = {};
  if (Number.isInteger(meta.itemLevel) && meta.itemLevel >= 1 && meta.itemLevel <= 99) {
    out.itemLevel = meta.itemLevel;
  }
  if (RARITIES.has(meta.rarity)) {
    out.rarity = meta.rarity;
  }
  if (meta.traits && typeof meta.traits === "object" && !Array.isArray(meta.traits)) {
    const traits = {};
    let count = 0;
    for (const [traitId, points] of Object.entries(meta.traits)) {
      if (
        typeof traitId === "string" &&
        traitId.length <= 32 &&
        Number.isInteger(points) &&
        points >= 1 &&
        points <= 30
      ) {
        traits[LEGACY_IDS[traitId] || traitId] = points;
        count += 1;
        if (count >= 4) break;
      }
    }
    if (count > 0) out.traits = traits;
  }
  return out.itemLevel || out.traits ? out : null;
}

// ---- placement helpers ------------------------------------------------------

function footprintOf(row) {
  return sizeFor(row.itemId, row.rotated);
}

function makeOccupancy(rows) {
  const occ = Array.from({ length: GRID.height }, () => new Array(GRID.width).fill(false));
  for (const row of rows) {
    if (row.containerId !== "main" || row.x === null) continue;
    const [w, h] = footprintOf(row);
    occupy(occ, row.x, row.y, w, h);
  }
  return occ;
}

function occupy(occ, x, y, w, h) {
  for (let dy = 0; dy < h; dy++) {
    for (let dx = 0; dx < w; dx++) {
      if (occ[y + dy]) occ[y + dy][x + dx] = true;
    }
  }
}

function fits(occ, x, y, w, h) {
  if (x < 0 || y < 0 || x + w > GRID.width || y + h > GRID.height) return false;
  for (let dy = 0; dy < h; dy++) {
    for (let dx = 0; dx < w; dx++) {
      if (occ[y + dy][x + dx]) return false;
    }
  }
  return true;
}

// First free spot for the item, trying unrotated then rotated.
function findSpot(occ, itemId) {
  const [w, h] = sizeFor(itemId, false);
  const orientations = w === h ? [false] : [false, true];
  for (const rotated of orientations) {
    const [tw, th] = rotated ? [h, w] : [w, h];
    for (let y = 0; y <= GRID.height - th; y++) {
      for (let x = 0; x <= GRID.width - tw; x++) {
        if (fits(occ, x, y, tw, th)) return { x, y, rotated };
      }
    }
  }
  return null;
}

// Repacks legacy flat-slot rows (x IS NULL) into grid positions, preserving
// their slot order. Returns true if anything changed.
async function migrateLegacyRows(client, rows) {
  const legacy = rows.filter((r) => r.containerId === "main" && r.x === null);
  if (legacy.length === 0) return false;

  const occ = makeOccupancy(rows);
  legacy.sort((a, b) => (a.slotIndex ?? 0) - (b.slotIndex ?? 0));
  for (const row of legacy) {
    const spot = findSpot(occ, row.itemId);
    if (!spot) {
      // A legacy 20-slot inventory always fits in 10x30; guard anyway.
      throw err("no room migrating legacy inventory", "no_room");
    }
    const [w, h] = sizeFor(row.itemId, spot.rotated);
    occupy(occ, spot.x, spot.y, w, h);
    await client.query(
      `UPDATE inventory_items
          SET container_id = 'main', x = $1, y = $2, rotated = $3, slot_index = NULL
        WHERE id = $4`,
      [spot.x, spot.y, spot.rotated, row.id]
    );
  }
  return true;
}

// Fetch rows, migrating legacy ones first so callers always see positions.
async function loadRows(client, playerId) {
  let rows = await fetchRows(client, playerId);
  if (await migrateLegacyRows(client, rows)) {
    rows = await fetchRows(client, playerId);
  }
  return rows;
}

// ---- public operations ------------------------------------------------------

// Returns the inventory as [{ containerId, x, y, rotated, itemId, quantity,
// meta? }] (meta only on rolled-item rows).
export async function getInventory(client, playerId) {
  const rows = await loadRows(client, playerId);
  return rows.map(({ containerId, x, y, rotated, itemId, quantity, meta }) => ({
    containerId,
    x,
    y,
    rotated,
    itemId,
    quantity,
    meta: meta || undefined,
  }));
}

// Adds `quantity` of `itemId` to the main grid: tops up partial stacks first,
// then places new stacks at the first spot their footprint fits (unrotated,
// then rotated). Throws { code: 'no_room' } if it can't all fit — unless
// `partial` is set, in which case it adds what fits and reports the rest
// (drop pickups use this so stackables can be picked up partially).
// With `meta` (a rolled instance) nothing merges: no top-up phase, and every
// inserted row carries the meta. Returns { added, remaining }.
export async function addItem(
  client,
  playerId,
  itemId,
  quantity,
  { partial = false, meta = null } = {}
) {
  if (!getItem(itemId)) {
    throw err(`unknown item: ${itemId}`, "unknown_item");
  }
  if (!Number.isInteger(quantity) || quantity <= 0) {
    throw err("quantity must be a positive integer", "bad_quantity");
  }
  const cleanMeta = sanitizeMeta(meta);

  const maxStack = maxStackFor(itemId);
  const rows = await loadRows(client, playerId);
  let remaining = quantity;

  // 1) top up existing partial stacks in the main grid (plain items only —
  //    instance rows never gain or give quantity)
  if (!cleanMeta) {
    for (const row of rows) {
      if (remaining <= 0) break;
      if (row.containerId !== "main" || row.itemId !== itemId || row.quantity >= maxStack) continue;
      if (row.meta) continue;
      const add = Math.min(maxStack - row.quantity, remaining);
      await client.query(
        `UPDATE inventory_items SET quantity = quantity + $1 WHERE id = $2`,
        [add, row.id]
      );
      remaining -= add;
    }
  }

  // 2) place new stacks wherever the footprint fits
  const occ = makeOccupancy(rows);
  while (remaining > 0) {
    const spot = findSpot(occ, itemId);
    if (!spot) break;
    const add = Math.min(maxStack, remaining);
    const [w, h] = sizeFor(itemId, spot.rotated);
    occupy(occ, spot.x, spot.y, w, h);
    await client.query(
      `INSERT INTO inventory_items (player_id, container_id, x, y, rotated, item_id, quantity, meta)
       VALUES ($1, 'main', $2, $3, $4, $5, $6, $7::jsonb)`,
      [playerId, spot.x, spot.y, spot.rotated, itemId, add, cleanMeta ? JSON.stringify(cleanMeta) : null]
    );
    remaining -= add;
  }

  if (remaining > 0 && !partial) {
    throw err("not enough inventory space", "no_room", { added: quantity - remaining });
  }
  return { added: quantity - remaining, remaining };
}

// Removes `quantity` of `itemId` from the main grid (equipped items are not
// touched), draining stacks from the bottom of the grid up. Rolled-item rows
// (meta) are never consumed by generic id-based removal — selling/crafting a
// unique instance needs an instance-aware verb (future work).
// Throws { code: 'insufficient' } if the player doesn't have that many.
export async function removeItem(client, playerId, itemId, quantity) {
  if (!Number.isInteger(quantity) || quantity <= 0) {
    throw err("quantity must be a positive integer", "bad_quantity");
  }

  // Equippable-and-consumable items (acampada, crafting_table, simple_forge,
  // ...) get moved to the "equipment" container the moment they're equipped
  // — placing one has to find it there too, not just in the main grid, or
  // an equipped-but-not-yet-placed piece looks "missing" to this check even
  // though it's sitting right there in the weapon/offhand slot.
  const rows = (await loadRows(client, playerId)).filter(
    (r) =>
      (r.containerId === "main" || r.containerId === "equipment") &&
      r.itemId === itemId &&
      !r.meta
  );
  const total = rows.reduce((sum, r) => sum + r.quantity, 0);
  if (total < quantity) {
    throw err("insufficient quantity", "insufficient");
  }

  let remaining = quantity;
  for (const row of rows.reverse()) {
    if (remaining <= 0) break;
    const take = Math.min(row.quantity, remaining);
    if (take === row.quantity) {
      await client.query(`DELETE FROM inventory_items WHERE id = $1`, [row.id]);
    } else {
      await client.query(
        `UPDATE inventory_items SET quantity = quantity - $1 WHERE id = $2`,
        [take, row.id]
      );
    }
    remaining -= take;
  }
  return { removed: quantity };
}

// Removes the entire stack at a specific position (drag-out-to-drop: the
// game turns it into a ground drop). Returns { itemId, quantity, meta? } so
// a thrown rolled item keeps its identity on the ground.
// Throws { code: 'bad_move' | 'not_found' }.
export async function removeAt(client, playerId, ref) {
  if (
    !ref ||
    (ref.containerId !== "main" && ref.containerId !== "equipment") ||
    !Number.isInteger(ref.x) ||
    !Number.isInteger(ref.y)
  ) {
    throw err("bad position reference", "bad_move");
  }
  const rows = await loadRows(client, playerId);
  const source = rows.find(
    (r) => r.containerId === ref.containerId && r.x === ref.x && r.y === ref.y
  );
  if (!source) {
    throw err("no item at position", "not_found");
  }
  await client.query(`DELETE FROM inventory_items WHERE id = $1`, [source.id]);
  return { itemId: source.itemId, quantity: source.quantity, meta: source.meta || undefined };
}

// Splits `quantity` off the stack at `ref` into a NEW stack at the first
// free grid spot — the "Dividir" context-menu action. The original stack
// stays right where it was with the remainder; nothing is thrown on the
// ground (that's still the separate "Soltar" action / removeAt above, on
// whichever of the two stacks the player picks afterwards).
// `quantity` must be a positive integer STRICTLY less than the stack's
// total (splitting off "everything" isn't a split, it's just the stack
// where it already is — the client doesn't offer that). Rolled instances
// (meta rows) can't be split — they're unique, there's nothing to divide.
// Throws { code: 'bad_move' | 'not_found' | 'bad_quantity' | 'no_room' }.
export async function splitStack(client, playerId, ref, quantity) {
  if (!ref || ref.containerId !== "main" || !Number.isInteger(ref.x) || !Number.isInteger(ref.y)) {
    throw err("bad position reference", "bad_move");
  }
  if (!Number.isInteger(quantity) || quantity <= 0) {
    throw err("quantity must be a positive integer", "bad_quantity");
  }

  const rows = await loadRows(client, playerId);
  const source = rows.find(
    (r) => r.containerId === "main" && r.x === ref.x && r.y === ref.y
  );
  if (!source) {
    throw err("no item at position", "not_found");
  }
  if (source.meta) {
    throw err("rolled items can't be split", "bad_quantity");
  }
  const def = getItem(source.itemId);
  if (!def || !def.stackable || quantity >= source.quantity) {
    throw err("quantity must be less than the stack", "bad_quantity");
  }

  // The source keeps occupying its own footprint (it isn't moving, only
  // shrinking) — occupancy from ALL current rows is exactly what a new,
  // separate stack needs to avoid landing on top of anything.
  const occ = makeOccupancy(rows);
  const spot = findSpot(occ, source.itemId);
  if (!spot) {
    throw err("no room to split", "no_room");
  }

  await client.query(
    `UPDATE inventory_items SET quantity = quantity - $1 WHERE id = $2`,
    [quantity, source.id]
  );
  await client.query(
    `INSERT INTO inventory_items (player_id, container_id, x, y, rotated, item_id, quantity, meta)
     VALUES ($1, 'main', $2, $3, $4, $5, $6, NULL)`,
    [playerId, spot.x, spot.y, spot.rotated, source.itemId, quantity]
  );
  return { split: true };
}

// Moves the stack at `from` to `to` (the drag & drop verb). Handles main-grid
// moves (with rotation), equip/unequip (slot compatibility validated), and
// merging when dropped onto a same-item stack.
//   from: { containerId, x, y }   to: { containerId, x, y, rotated? }
// Throws { code: 'bad_move' | 'not_found' | 'bad_slot' | 'out_of_bounds' | 'blocked' }.
export async function moveItem(client, playerId, from, to) {
  for (const ref of [from, to]) {
    if (
      !ref ||
      (ref.containerId !== "main" && ref.containerId !== "equipment") ||
      !Number.isInteger(ref.x) ||
      !Number.isInteger(ref.y)
    ) {
      throw err("bad move reference", "bad_move");
    }
  }
  const rotated = to.rotated === true;

  const rows = await loadRows(client, playerId);
  const source = rows.find(
    (r) => r.containerId === from.containerId && r.x === from.x && r.y === from.y
  );
  if (!source) {
    throw err("no item at source position", "not_found");
  }
  const def = getItem(source.itemId);

  if (to.containerId === "equipment") {
    const slotName = EQUIPMENT_SLOTS[to.x];
    if (!slotName || to.y !== 0) throw err("bad equipment slot", "bad_slot");
    if (!slotAccepts(slotName, def)) throw err("item can't go in that slot", "bad_slot");
    const occupied = rows.some(
      (r) => r.id !== source.id && r.containerId === "equipment" && r.x === to.x
    );
    if (occupied) throw err("slot occupied", "blocked");
    await client.query(
      `UPDATE inventory_items
          SET container_id = 'equipment', x = $1, y = 0, rotated = false
        WHERE id = $2`,
      [to.x, source.id]
    );
    return { moved: true };
  }

  // Destination: main grid.
  const [w, h] = sizeFor(source.itemId, rotated);
  if (to.x < 0 || to.y < 0 || to.x + w > GRID.width || to.y + h > GRID.height) {
    throw err("out of bounds", "out_of_bounds");
  }

  const overlapping = rows.filter((r) => {
    if (r.id === source.id || r.containerId !== "main" || r.x === null) return false;
    const [rw, rh] = footprintOf(r);
    return r.x < to.x + w && to.x < r.x + rw && r.y < to.y + h && to.y < r.y + rh;
  });

  if (overlapping.length === 0) {
    await client.query(
      `UPDATE inventory_items
          SET container_id = 'main', x = $1, y = $2, rotated = $3
        WHERE id = $4`,
      [to.x, to.y, rotated, source.id]
    );
    return { moved: true };
  }

  // Dropped onto a single same-item stack: merge as much as fits. Instance
  // rows (meta) never merge — each is a distinct item.
  const target = overlapping[0];
  const maxStack = maxStackFor(source.itemId);
  if (
    overlapping.length === 1 &&
    target.itemId === source.itemId &&
    def.stackable &&
    !source.meta &&
    !target.meta &&
    target.quantity < maxStack
  ) {
    const transfer = Math.min(maxStack - target.quantity, source.quantity);
    await client.query(
      `UPDATE inventory_items SET quantity = quantity + $1 WHERE id = $2`,
      [transfer, target.id]
    );
    if (transfer === source.quantity) {
      await client.query(`DELETE FROM inventory_items WHERE id = $1`, [source.id]);
    } else {
      await client.query(
        `UPDATE inventory_items SET quantity = quantity - $1 WHERE id = $2`,
        [transfer, source.id]
      );
    }
    return { moved: true, merged: transfer };
  }

  throw err("destination blocked", "blocked");
}

// Sort order for the repack: gear first, materials last.
const TYPE_ORDER = { weapon: 1, tool: 2, armor: 3, ring: 4, backpack: 5, resource: 6 };

// Repacks the main grid: plain stacks merged to full and ordered by type
// then id; rolled-item rows (meta) are preserved verbatim as their own
// stacks — sorting must NEVER fuse or wipe instance data. Equipment is
// untouched.
export async function sortInventory(client, playerId) {
  const rows = (await loadRows(client, playerId)).filter((r) => r.containerId === "main");

  const totals = new Map();
  for (const row of rows) {
    if (row.meta) continue;
    totals.set(row.itemId, (totals.get(row.itemId) || 0) + row.quantity);
  }

  const stacks = [];
  for (const [itemId, total] of totals) {
    const maxStack = maxStackFor(itemId);
    let left = total;
    while (left > 0) {
      const qty = Math.min(maxStack, left);
      stacks.push({ itemId, quantity: qty, meta: null });
      left -= qty;
    }
  }
  for (const row of rows) {
    if (row.meta) stacks.push({ itemId: row.itemId, quantity: row.quantity, meta: row.meta });
  }
  stacks.sort((a, b) => {
    const ta = TYPE_ORDER[getItem(a.itemId).type] || 99;
    const tb = TYPE_ORDER[getItem(b.itemId).type] || 99;
    if (ta !== tb) return ta - tb;
    if (a.itemId !== b.itemId) return a.itemId < b.itemId ? -1 : 1;
    return b.quantity - a.quantity;
  });

  await client.query(
    `DELETE FROM inventory_items WHERE player_id = $1 AND container_id = 'main'`,
    [playerId]
  );
  const occ = makeOccupancy([]);
  for (const stack of stacks) {
    const spot = findSpot(occ, stack.itemId);
    if (!spot) {
      // Repacking the same items can't need more space; guard anyway (the
      // transaction rolls back, leaving the inventory untouched).
      throw err("sort could not fit items", "no_room");
    }
    const [w, h] = sizeFor(stack.itemId, spot.rotated);
    occupy(occ, spot.x, spot.y, w, h);
    await client.query(
      `INSERT INTO inventory_items (player_id, container_id, x, y, rotated, item_id, quantity, meta)
       VALUES ($1, 'main', $2, $3, $4, $5, $6, $7::jsonb)`,
      [playerId, spot.x, spot.y, spot.rotated, stack.itemId, stack.quantity,
        stack.meta ? JSON.stringify(stack.meta) : null]
    );
  }
  return { sorted: true };
}