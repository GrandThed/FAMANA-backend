// Per-player event queue for pushing admin changes to online players. The game
// polls drainEvents() for its online users; admin mutations enqueue rows.

import { query } from "./db.js";

// Enqueue an event inside an existing transaction (so it commits atomically
// with the mutation that caused it).
export function enqueueEvent(client, playerId, kind, message, payload = {}) {
  return client.query(
    `INSERT INTO player_events (player_id, kind, message, payload)
     VALUES ($1, $2, $3, $4)`,
    [playerId, kind, message ?? null, JSON.stringify(payload ?? {})]
  );
}

// Atomically return and remove all pending events for the given user ids.
// Called by the game's poll loop.
export async function drainEvents(userIds) {
  if (!Array.isArray(userIds) || userIds.length === 0) return [];
  const ids = userIds.map(Number).filter((n) => Number.isInteger(n) && n > 0);
  if (ids.length === 0) return [];

  const { rows } = await query(
    `DELETE FROM player_events
      WHERE player_id = ANY($1::bigint[])
      RETURNING player_id::text AS "playerId", kind, message, payload`,
    [ids]
  );
  return rows;
}
