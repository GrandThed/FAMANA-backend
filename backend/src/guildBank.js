// Guild bank: a shared, flat (non-spatial) item stockpile per guild — see
// schema.sql's guild_bank_items for why it's not a grid like the player's
// own inventory. Every deposit/withdraw is one transaction that moves the
// stack in the same breath as touching the player's own inventory (via
// inventory.js's addItem/removeItem), so there's never a moment where an
// item exists in neither place, or in both.

import { pool, withTransaction } from "./db.js";
import { removeItem, addItem } from "./inventory.js";
import { getItem } from "./items.js";

function bankError(code) {
  return Object.assign(new Error(code), { code });
}

async function requireMembership(client, guildId, playerId) {
  const { rows } = await client.query(
    `SELECT role FROM guild_members WHERE guild_id = $1 AND player_id = $2`,
    [guildId, playerId]
  );
  if (rows.length === 0) throw bankError("not_member");
  return rows[0].role;
}

async function requireGuild(client, guildId) {
  const { rows } = await client.query(`SELECT leader_id FROM guilds WHERE id = $1`, [guildId]);
  if (rows.length === 0) throw bankError("guild_not_found");
  return rows[0];
}

export async function getBank(guildId) {
  const { rows } = await pool.query(
    `SELECT item_id, quantity FROM guild_bank_items WHERE guild_id = $1 ORDER BY item_id`,
    [guildId]
  );
  return rows.map((r) => ({ itemId: r.item_id, quantity: r.quantity }));
}

export async function getBankLog(guildId, limit = 30) {
  const { rows } = await pool.query(
    `SELECT l.player_id, p.username, l.item_id, l.quantity, l.action, l.created_at
       FROM guild_bank_log l
       LEFT JOIN players p ON p.id = l.player_id
      WHERE l.guild_id = $1
      ORDER BY l.created_at DESC
      LIMIT $2`,
    [guildId, Math.min(Math.max(1, limit), 100)]
  );
  return rows.map((r) => ({
    playerId: r.player_id === null ? null : String(r.player_id),
    username: r.username || "?",
    itemId: r.item_id,
    quantity: r.quantity,
    action: r.action,
    createdAt: r.created_at,
  }));
}

// Any member (not just officers) can deposit — restricting *giving* the
// guild items would be a strange rule. Pulls the stack straight out of the
// player's own inventory via inventory.js's own grid-aware removeItem, so
// it fails the same way ("insufficient") a player short on an item would
// expect from any other transfer.
// Throws { code: "unknown_item" | "not_member" | "insufficient" | "bad_quantity" }.
export async function depositItem(guildId, playerId, itemId, quantity) {
  if (!getItem(itemId)) throw bankError("unknown_item");
  return withTransaction(async (client) => {
    await requireMembership(client, guildId, playerId);
    await removeItem(client, playerId, itemId, quantity, { includeMeta: true }); // throws insufficient/bad_quantity
    await client.query(
      `INSERT INTO guild_bank_items (guild_id, item_id, quantity)
            VALUES ($1, $2, $3)
       ON CONFLICT (guild_id, item_id) DO UPDATE SET quantity = guild_bank_items.quantity + $3`,
      [guildId, itemId, quantity]
    );
    await client.query(
      `INSERT INTO guild_bank_log (guild_id, player_id, item_id, quantity, action)
            VALUES ($1, $2, $3, $4, 'deposit')`,
      [guildId, playerId, itemId, quantity]
    );
    return { deposited: quantity };
  });
}

// Officer/leader only — a bank anyone could drain invites exactly the
// drama a "roles" feature exists to prevent. Runs addItem with
// partial:true: if the withdrawer's own inventory doesn't have room for the
// full amount, only that much comes out of the bank rather than the rest
// vanishing — the remainder simply stays banked for a later trip.
// Throws { code: "unknown_item" | "not_member" | "not_authorized" |
//          "insufficient" | "no_room" | "guild_not_found" }.
export async function withdrawItem(guildId, playerId, itemId, quantity) {
  if (!getItem(itemId)) throw bankError("unknown_item");
  return withTransaction(async (client) => {
    const guild = await requireGuild(client, guildId);
    const role = await requireMembership(client, guildId, playerId);
    const isLeader = String(guild.leader_id) === String(playerId);
    if (!isLeader && role !== "officer") {
      throw bankError("not_authorized");
    }

    const { rows } = await client.query(
      `SELECT quantity FROM guild_bank_items WHERE guild_id = $1 AND item_id = $2 FOR UPDATE`,
      [guildId, itemId]
    );
    const available = rows[0] ? rows[0].quantity : 0;
    if (available < quantity) throw bankError("insufficient");

    const { added } = await addItem(client, playerId, itemId, quantity, { partial: true });
    if (added <= 0) throw bankError("no_room");

    if (added === available) {
      await client.query(`DELETE FROM guild_bank_items WHERE guild_id = $1 AND item_id = $2`, [guildId, itemId]);
    } else {
      await client.query(
        `UPDATE guild_bank_items SET quantity = quantity - $1 WHERE guild_id = $2 AND item_id = $3`,
        [added, guildId, itemId]
      );
    }
    await client.query(
      `INSERT INTO guild_bank_log (guild_id, player_id, item_id, quantity, action)
            VALUES ($1, $2, $3, $4, 'withdraw')`,
      [guildId, playerId, itemId, added]
    );
    return { withdrawn: added };
  });
}
