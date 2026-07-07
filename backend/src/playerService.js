// Player persistence: load, create (with starter items), and coarse save.

import { withTransaction, query } from "./db.js";
import { getInventory, addItem } from "./inventory.js";
import { STARTER_ITEMS, STARTER_EQUIPPABLES } from "./items.js";
import { isValidClass, defaultClassLevels, DEFAULT_CLASS } from "./classes.js";

// Grants any missing starter tools/weapons (idempotent). Lets existing players
// pick up newly-added starter gear without wiping their profile.
async function ensureStarterEquippables(client, playerId, inventory) {
  const owned = new Set(inventory.map((entry) => entry.itemId));
  let granted = false;
  for (const item of STARTER_EQUIPPABLES) {
    if (!owned.has(item.itemId)) {
      await addItem(client, playerId, item.itemId, item.quantity);
      granted = true;
    }
  }
  return granted;
}

function rowToPlayer(row, inventory) {
  const currentClass = isValidClass(row.current_class) ? row.current_class : DEFAULT_CLASS;

  // Profiles saved before the class system existed come back with an empty
  // class_levels blob. Migrate: seed the active class's track from the old
  // flat level/xp columns so nobody loses progress; every other class
  // starts fresh at level 1. (Mirrors the same migration in PlayerService.lua.)
  const classLevels = row.class_levels && Object.keys(row.class_levels).length > 0
    ? row.class_levels
    : { ...defaultClassLevels(), [currentClass]: { level: row.level, xp: Number(row.xp) } };

  return {
    id: String(row.id),
    username: row.username,
    health: row.health,
    maxHealth: row.max_health,
    gold: Number(row.gold), // BIGINT arrives as a string from pg
    level: row.level,
    xp: Number(row.xp), // BIGINT arrives as a string from pg
    currentClass,
    classLevels,
    hotbarBinds: row.hotbar_binds || {},
    settings: row.settings || {},

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
    let inventory = await getInventory(client, playerId);
    if (await ensureStarterEquippables(client, playerId, inventory)) {
      inventory = await getInventory(client, playerId);
    }
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
      `INSERT INTO players (id, username, current_class, class_levels)
       VALUES ($1, $2, $3, $4::jsonb) RETURNING *`,
      [playerId, username, DEFAULT_CLASS, JSON.stringify(defaultClassLevels())]
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
export async function savePlayer(playerId, { health, gold, level, xp, currentClass, classLevels, hotbarBinds, settings, cell, position }) {
  const sets = [];
  const params = [];
  let i = 1;

  if (health !== undefined) { sets.push(`health = $${i++}`); params.push(health); }
  if (gold !== undefined) { sets.push(`gold = $${i++}`); params.push(gold); }
  if (level !== undefined) { sets.push(`level = $${i++}`); params.push(level); }
  if (xp !== undefined) { sets.push(`xp = $${i++}`); params.push(xp); }
  if (currentClass !== undefined && isValidClass(currentClass)) {
    sets.push(`current_class = $${i++}`);
    params.push(currentClass);
  }
  if (classLevels !== undefined) {
    // Same JSONB-stringify caveat as hotbarBinds: an empty Luau table
    // arrives as [], which node-pg would otherwise send as a Postgres array.
    sets.push(`class_levels = $${i++}::jsonb`);
    params.push(JSON.stringify(classLevels ?? {}));
  }
  if (hotbarBinds !== undefined) {
    // Stringify explicitly: an empty Luau table arrives as [] and node-pg
    // would otherwise send arrays in Postgres array syntax, not JSON.
    sets.push(`hotbar_binds = $${i++}::jsonb`);
    params.push(JSON.stringify(hotbarBinds ?? {}));
  }
  if (settings !== undefined) {
    // Same JSONB-stringify caveat as hotbarBinds.
    sets.push(`settings = $${i++}::jsonb`);
    params.push(JSON.stringify(settings ?? {}));
  }
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
