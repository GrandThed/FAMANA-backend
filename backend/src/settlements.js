// Territory: ownership of settlement points-of-interest, claimed by guilds
// after their Roblox server reports a guardian/challenger kill. This module
// never decides *who* wins a capture — that's decided in Roblox (top damage
// on the guardian, per design) — it only persists the outcome and enforces
// the grace window so a capture can't be flipped back the instant it lands.
//
// settlement_id is whatever key the Roblox side uses (shared/Settlements.lua)
// — there's no registry of valid ids here, same MVP tradeoff as guild tags
// not being reserved ahead of creation.

import { pool, withTransaction } from "./db.js";

const DEFAULT_GRACE_SECONDS = 600; // 10 min

function settlementError(code) {
  return Object.assign(new Error(code), { code });
}

function rowToClaim(settlementId, row) {
  if (!row || !row.guild_id) {
    return { settlementId, guildId: null, claimedAt: null, graceUntil: null };
  }
  return {
    settlementId,
    guildId: String(row.guild_id),
    claimedAt: row.claimed_at,
    graceUntil: row.grace_until,
  };
}

// All settlements that currently have an owner (neutral ones simply have no
// row, or a row with guild_id NULL after a disband — both are omitted).
// Used to paint the map on load; polled rather than pushed since ownership
// changes are rare relative to how often a client might reconnect.
export async function listClaims() {
  const { rows } = await pool.query(
    `SELECT settlement_id, guild_id, claimed_at, grace_until
       FROM settlement_claims
      WHERE guild_id IS NOT NULL`
  );
  return rows.map((r) => rowToClaim(r.settlement_id, r));
}

export async function getClaim(settlementId) {
  const { rows } = await pool.query(
    `SELECT guild_id, claimed_at, grace_until FROM settlement_claims WHERE settlement_id = $1`,
    [settlementId]
  );
  return rowToClaim(settlementId, rows[0]);
}

// Records a capture: `guildId` now owns `settlementId`. `killerId` (a player
// id, optional) is credited in the history table for a future "captured by"
// UI. Throws { code: "in_grace", graceUntil } if the settlement is still
// protected from its last capture — the Roblox side should treat this as
// "the challenger fight shouldn't have been possible" and just no-op/log it,
// since the grace window is meant to be enforced client-side too (this is
// the backstop, not the primary defense).
export async function claimSettlement(settlementId, guildId, killerId, graceSeconds = DEFAULT_GRACE_SECONDS) {
  return withTransaction(async (client) => {
    const { rows } = await client.query(
      `SELECT guild_id, grace_until FROM settlement_claims WHERE settlement_id = $1 FOR UPDATE`,
      [settlementId]
    );
    const current = rows[0];

    if (current && String(current.guild_id) === String(guildId)) {
      // Already theirs (e.g. a duplicate report from a retry) — no-op,
      // don't reset the grace clock.
      return rowToClaim(settlementId, current);
    }

    if (current && current.grace_until && new Date(current.grace_until) > new Date()) {
      throw Object.assign(settlementError("in_grace"), { graceUntil: current.grace_until });
    }

    const previousGuildId = current ? current.guild_id : null;

    const upserted = await client.query(
      `INSERT INTO settlement_claims (settlement_id, guild_id, claimed_at, grace_until)
            VALUES ($1, $2, now(), now() + ($3 || ' seconds')::interval)
       ON CONFLICT (settlement_id)
       DO UPDATE SET guild_id = $2, claimed_at = now(), grace_until = now() + ($3 || ' seconds')::interval
       RETURNING guild_id, claimed_at, grace_until`,
      [settlementId, guildId, String(graceSeconds)]
    );

    await client.query(
      `INSERT INTO settlement_captures (settlement_id, guild_id, captured_from, player_id)
            VALUES ($1, $2, $3, $4)`,
      [settlementId, guildId, previousGuildId, killerId || null]
    );

    return rowToClaim(settlementId, upserted.rows[0]);
  });
}

// Manual/admin release back to neutral (e.g. moderation, or a future "guild
// abandons territory" action). Not used by the guardian-kill flow itself —
// that always transfers straight to the new owner via claimSettlement.
export async function releaseSettlement(settlementId) {
  await pool.query(
    `UPDATE settlement_claims SET guild_id = NULL, grace_until = NULL WHERE settlement_id = $1`,
    [settlementId]
  );
}
