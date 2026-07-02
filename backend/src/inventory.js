// Inventory mutation logic. All operations run inside a transaction so
// concurrent server hops can't lose or duplicate items.

import { getItem, maxStackFor, INVENTORY_CAPACITY } from "./items.js";

// Returns the player's inventory as an array of { slotIndex, itemId, quantity }.
export async function getInventory(client, playerId) {
  const { rows } = await client.query(
    `SELECT slot_index AS "slotIndex", item_id AS "itemId", quantity
       FROM inventory_items
      WHERE player_id = $1
      ORDER BY slot_index`,
    [playerId]
  );
  return rows;
}

// Adds `quantity` of `itemId`: fills existing partial stacks first, then empty
// slots. Throws { code: 'unknown_item' | 'no_room' } on failure.
export async function addItem(client, playerId, itemId, quantity) {
  if (!getItem(itemId)) {
    throw Object.assign(new Error(`unknown item: ${itemId}`), { code: "unknown_item" });
  }
  if (!Number.isInteger(quantity) || quantity <= 0) {
    throw Object.assign(new Error("quantity must be a positive integer"), { code: "bad_quantity" });
  }

  const maxStack = maxStackFor(itemId);
  const rows = await getInventory(client, playerId);
  let remaining = quantity;

  // 1) top up existing partial stacks of the same item
  for (const row of rows) {
    if (remaining <= 0) break;
    if (row.itemId !== itemId || row.quantity >= maxStack) continue;
    const space = maxStack - row.quantity;
    const add = Math.min(space, remaining);
    await client.query(
      `UPDATE inventory_items SET quantity = quantity + $1
        WHERE player_id = $2 AND slot_index = $3`,
      [add, playerId, row.slotIndex]
    );
    remaining -= add;
  }

  // 2) fill empty slots
  if (remaining > 0) {
    const used = new Set(rows.map((r) => r.slotIndex));
    for (let slot = 0; slot < INVENTORY_CAPACITY && remaining > 0; slot++) {
      if (used.has(slot)) continue;
      const add = Math.min(maxStack, remaining);
      await client.query(
        `INSERT INTO inventory_items (player_id, slot_index, item_id, quantity)
         VALUES ($1, $2, $3, $4)`,
        [playerId, slot, itemId, add]
      );
      remaining -= add;
    }
  }

  if (remaining > 0) {
    throw Object.assign(new Error("not enough inventory space"), {
      code: "no_room",
      added: quantity - remaining,
    });
  }
  return { added: quantity };
}

// Removes `quantity` of `itemId`, draining slots from the highest index down.
// Throws { code: 'insufficient' } if the player doesn't have that many.
export async function removeItem(client, playerId, itemId, quantity) {
  if (!Number.isInteger(quantity) || quantity <= 0) {
    throw Object.assign(new Error("quantity must be a positive integer"), { code: "bad_quantity" });
  }

  const rows = (await getInventory(client, playerId)).filter((r) => r.itemId === itemId);
  const total = rows.reduce((sum, r) => sum + r.quantity, 0);
  if (total < quantity) {
    throw Object.assign(new Error("insufficient quantity"), { code: "insufficient" });
  }

  let remaining = quantity;
  for (const row of rows.reverse()) {
    if (remaining <= 0) break;
    const take = Math.min(row.quantity, remaining);
    if (take === row.quantity) {
      await client.query(
        `DELETE FROM inventory_items WHERE player_id = $1 AND slot_index = $2`,
        [playerId, row.slotIndex]
      );
    } else {
      await client.query(
        `UPDATE inventory_items SET quantity = quantity - $1
          WHERE player_id = $2 AND slot_index = $3`,
        [take, playerId, row.slotIndex]
      );
    }
    remaining -= take;
  }
  return { removed: quantity };
}
