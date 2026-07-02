// Data layer for the admin dashboard. Read aggregates + guarded mutations.
// Every mutation writes an admin_audit row inside the same transaction.

import { query, withTransaction } from "./db.js";
import { getInventory, addItem, removeItem } from "./inventory.js";
import { enqueueEvent } from "./events.js";
import { ITEMS } from "./items.js";

function itemName(itemId) {
  return ITEMS[itemId]?.name || itemId;
}

// Whitelist of sortable columns → SQL, so we never interpolate user input.
const SORT_COLUMNS = {
  updated_at: "updated_at",
  created_at: "created_at",
  username: "username",
  cell: "cell",
  health: "health",
  id: "id",
};

function auditInsert(client, { actor, action, targetPlayer, detail }) {
  return client.query(
    `INSERT INTO admin_audit (actor, action, target_player, detail)
     VALUES ($1, $2, $3, $4)`,
    [actor, action, targetPlayer ?? null, JSON.stringify(detail ?? {})]
  );
}

// --- reads ------------------------------------------------------------------

export async function getStats() {
  const [byCell, itemTotals, totals, active24, new7] = await Promise.all([
    query(`SELECT cell, COUNT(*)::int AS n FROM players GROUP BY cell ORDER BY cell`),
    query(
      `SELECT item_id, SUM(quantity)::int AS total
         FROM inventory_items GROUP BY item_id ORDER BY item_id`
    ),
    query(`SELECT COUNT(*)::int AS n FROM players`),
    query(
      `SELECT COUNT(*)::int AS n FROM players WHERE updated_at > now() - interval '24 hours'`
    ),
    query(`SELECT COUNT(*)::int AS n FROM players WHERE created_at > now() - interval '7 days'`),
  ]);

  return {
    players: {
      total: totals.rows[0].n,
      byCell: Object.fromEntries(byCell.rows.map((r) => [r.cell, r.n])),
    },
    activity: {
      activeLast24h: active24.rows[0].n,
      newLast7d: new7.rows[0].n,
    },
    items: Object.fromEntries(itemTotals.rows.map((r) => [r.item_id, r.total])),
  };
}

// Paginated, searchable player list. Returns { players, total }.
export async function listPlayers({ query: search, cell, limit, offset, sort } = {}) {
  const where = [];
  const params = [];
  let i = 1;

  if (search) {
    // Match username (case-insensitive) or exact numeric id.
    const asId = /^\d+$/.test(search) ? search : null;
    if (asId) {
      where.push(`(username ILIKE $${i} OR id = $${i + 1})`);
      params.push(`%${search}%`, asId);
      i += 2;
    } else {
      where.push(`username ILIKE $${i}`);
      params.push(`%${search}%`);
      i += 1;
    }
  }
  if (cell) {
    where.push(`cell = $${i}`);
    params.push(cell);
    i += 1;
  }

  const whereSql = where.length ? `WHERE ${where.join(" AND ")}` : "";

  // sort format: "column" or "column:desc"
  const [rawCol, rawDir] = String(sort || "updated_at:desc").split(":");
  const col = SORT_COLUMNS[rawCol] || "updated_at";
  const dir = rawDir && rawDir.toLowerCase() === "asc" ? "ASC" : "DESC";

  const lim = Math.min(Math.max(Number(limit) || 25, 1), 100);
  const off = Math.max(Number(offset) || 0, 0);

  const countPromise = query(`SELECT COUNT(*)::int AS n FROM players ${whereSql}`, params);
  const rowsPromise = query(
    `SELECT id::text, username, cell, health, max_health AS "maxHealth", updated_at AS "updatedAt"
       FROM players ${whereSql}
      ORDER BY ${col} ${dir}
      LIMIT $${i} OFFSET $${i + 1}`,
    [...params, lim, off]
  );

  const [countRes, rowsRes] = await Promise.all([countPromise, rowsPromise]);
  return { players: rowsRes.rows, total: countRes.rows[0].n, limit: lim, offset: off };
}

// Full player + inventory, or null.
export async function getPlayerDetail(playerId) {
  return withTransaction(async (client) => {
    const { rows } = await client.query(`SELECT * FROM players WHERE id = $1`, [playerId]);
    if (rows.length === 0) return null;
    const inventory = await getInventory(client, playerId);
    const row = rows[0];
    return {
      id: String(row.id),
      username: row.username,
      health: row.health,
      maxHealth: row.max_health,
      cell: row.cell,
      position: { x: row.pos_x, y: row.pos_y, z: row.pos_z },
      createdAt: row.created_at,
      updatedAt: row.updated_at,
      inventory,
    };
  });
}

export function getItemCatalog() {
  return Object.values(ITEMS).map((it) => ({
    id: it.id,
    name: it.name,
    type: it.type,
    stackable: it.stackable,
    maxStack: it.maxStack,
  }));
}

// --- mutations --------------------------------------------------------------

// Updates any of health / maxHealth / cell / position. Validates and audits.
// Throws { code } on bad input; returns null if the player doesn't exist.
export async function updatePlayer(playerId, patch, actor) {
  const sets = [];
  const params = [];
  const applied = {};
  let i = 1;

  if (patch.maxHealth !== undefined) {
    const v = Number(patch.maxHealth);
    if (!Number.isInteger(v) || v <= 0) throw fieldError("maxHealth");
    sets.push(`max_health = $${i++}`);
    params.push(v);
    applied.maxHealth = v;
  }
  if (patch.health !== undefined) {
    const v = Number(patch.health);
    if (!Number.isInteger(v) || v < 0) throw fieldError("health");
    sets.push(`health = $${i++}`);
    params.push(v);
    applied.health = v;
  }
  if (patch.cell !== undefined) {
    if (typeof patch.cell !== "string" || patch.cell.length === 0) throw fieldError("cell");
    sets.push(`cell = $${i++}`);
    params.push(patch.cell);
    applied.cell = patch.cell;
  }
  if (patch.position !== undefined) {
    const p = patch.position;
    for (const axis of ["x", "y", "z"]) {
      if (typeof p?.[axis] !== "number" || !Number.isFinite(p[axis])) throw fieldError("position");
    }
    sets.push(`pos_x = $${i++}`, `pos_y = $${i++}`, `pos_z = $${i++}`);
    params.push(p.x, p.y, p.z);
    applied.position = { x: p.x, y: p.y, z: p.z };
  }

  if (sets.length === 0) throw Object.assign(new Error("no fields"), { code: "no_fields" });

  // Clamp health to maxHealth when both are known post-update.
  sets.push(`updated_at = now()`);
  params.push(playerId);

  return withTransaction(async (client) => {
    const { rowCount } = await client.query(
      `UPDATE players SET ${sets.join(", ")} WHERE id = $${i}`,
      params
    );
    if (rowCount === 0) return null;
    // Guard against health > max_health after the edit.
    await client.query(`UPDATE players SET health = max_health WHERE id = $1 AND health > max_health`, [
      playerId,
    ]);
    await auditInsert(client, {
      actor,
      action: "update_player",
      targetPlayer: playerId,
      detail: applied,
    });
    return true;
  });
}

export async function adminAddItem(playerId, itemId, quantity, actor) {
  return withTransaction(async (client) => {
    const exists = await client.query(`SELECT 1 FROM players WHERE id = $1`, [playerId]);
    if (exists.rowCount === 0) return null;
    const result = await addItem(client, playerId, itemId, quantity);
    await auditInsert(client, {
      actor,
      action: "add_item",
      targetPlayer: playerId,
      detail: { itemId, quantity },
    });
    await enqueueEvent(
      client,
      playerId,
      "inventory",
      `An admin gave you ${quantity}× ${itemName(itemId)}.`,
      { action: "add", itemId, quantity }
    );
    const inventory = await getInventory(client, playerId);
    return { ...result, inventory };
  });
}

export async function adminRemoveItem(playerId, itemId, quantity, actor) {
  return withTransaction(async (client) => {
    const exists = await client.query(`SELECT 1 FROM players WHERE id = $1`, [playerId]);
    if (exists.rowCount === 0) return null;
    const result = await removeItem(client, playerId, itemId, quantity);
    await auditInsert(client, {
      actor,
      action: "remove_item",
      targetPlayer: playerId,
      detail: { itemId, quantity },
    });
    await enqueueEvent(
      client,
      playerId,
      "inventory",
      `An admin removed ${quantity}× ${itemName(itemId)} from your inventory.`,
      { action: "remove", itemId, quantity }
    );
    const inventory = await getInventory(client, playerId);
    return { ...result, inventory };
  });
}

export async function deletePlayer(playerId, actor) {
  return withTransaction(async (client) => {
    const { rows } = await client.query(
      `DELETE FROM players WHERE id = $1 RETURNING username`,
      [playerId]
    );
    if (rows.length === 0) return null;
    await auditInsert(client, {
      actor,
      action: "delete_player",
      targetPlayer: playerId,
      detail: { username: rows[0].username },
    });
    return true;
  });
}

function fieldError(field) {
  return Object.assign(new Error(`invalid ${field}`), { code: "bad_field", field });
}
