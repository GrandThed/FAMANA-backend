// Player persistence: load, create (with starter items), and coarse save.

import { withTransaction, query } from "./db.js";
import { getInventory, addItem } from "./inventory.js";
import { STARTER_ITEMS } from "./items.js";

function rowToPlayer(row, inventory) {
  return {
    id: String(row.id),
    username: row.username,
    health: row.health,
    maxHealth: row.max_health,
    cell: row.cell,
    position: { x: row.pos_x, y: row.pos_y, z: row.pos_z },
    inventory,
  };
}

// Returns the full player state, or null if they don't exist yet.
export async function loadPlayer(playerId) {
  return withTransaction(async (client) => {
    const { rows } = await client.query(`SELECT * FROM players WHERE id = $1`, [playerId]);
    if (rows.length === 0) return null;
    const inventory = await getInventory(client, playerId);
    return rowToPlayer(rows[0], inventory);
  });
}

// Creates a new player with default stats and starter items. Idempotent:
// if the player already exists, returns the existing record unchanged.
export async function createPlayer(playerId, username) {
  return withTransaction(async (client) => {
    const existing = await client.query(`SELECT * FROM players WHERE id = $1`, [playerId]);
    if (existing.rows.length > 0) {
      const inventory = await getInventory(client, playerId);
      return rowToPlayer(existing.rows[0], inventory);
    }

    const { rows } = await client.query(
      `INSERT INTO players (id, username) VALUES ($1, $2) RETURNING *`,
      [playerId, username]
    );
    for (const item of STARTER_ITEMS) {
      await addItem(client, playerId, item.itemId, item.quantity);
    }
    const inventory = await getInventory(client, playerId);
    return rowToPlayer(rows[0], inventory);
  });
}

// Saves the coarse mutable fields. Only provided fields are updated.
// Returns false if the player doesn't exist.
export async function savePlayer(playerId, { health, cell, position }) {
  const sets = [];
  const params = [];
  let i = 1;

  if (health !== undefined) { sets.push(`health = $${i++}`); params.push(health); }
  if (cell !== undefined) { sets.push(`cell = $${i++}`); params.push(cell); }
  if (position !== undefined) {
    sets.push(`pos_x = $${i++}`); params.push(position.x);
    sets.push(`pos_y = $${i++}`); params.push(position.y);
    sets.push(`pos_z = $${i++}`); params.push(position.z);
  }
  sets.push(`updated_at = now()`);

  params.push(playerId);
  const { rowCount } = await query(
    `UPDATE players SET ${sets.join(", ")} WHERE id = $${i}`,
    params
  );
  return rowCount > 0;
}
