import { query } from "../db.js";

// Top-N players by a chosen metric. Registered behind X-Api-Key like the
// rest of the game API (server.js) — it's read by the Roblox server on
// behalf of whoever opens LeaderboardUI, never fetched by the client
// directly. See docs/ACHIEVEMENTS.md §Leaderboards.
//
// `kills` sums bestiary_kills' JSONB values in SQL rather than in JS: with
// hundreds of players that's one aggregate query instead of hundreds of
// row-by-row sums.
const METRICS = {
  level: {
    label: "Level",
    select: "level AS score",
    orderBy: "level DESC",
  },
  gold: {
    label: "Gold",
    select: "gold AS score",
    orderBy: "gold DESC",
  },
  kills: {
    label: "Bestiary kills",
    select: `COALESCE((
      SELECT SUM(value::int) FROM jsonb_each_text(bestiary_kills)
    ), 0) AS score`,
    orderBy: "score DESC",
  },
};

const DEFAULT_LIMIT = 20;
const MAX_LIMIT = 100;

export default async function leaderboardRoutes(fastify) {
  fastify.get("/leaderboards", async (request, reply) => {
    const type = String(request.query?.type || "level");
    const metric = METRICS[type];
    if (!metric) {
      reply.code(400);
      return { error: "unknown_metric", metrics: Object.keys(METRICS) };
    }

    let limit = parseInt(request.query?.limit, 10);
    if (!Number.isFinite(limit) || limit < 1) limit = DEFAULT_LIMIT;
    limit = Math.min(limit, MAX_LIMIT);

    const result = await query(
      `SELECT id, username, ${metric.select}
       FROM players
       ORDER BY ${metric.orderBy}
       LIMIT $1`,
      [limit]
    );

    return {
      type,
      label: metric.label,
      entries: result.rows.map((row, index) => ({
        rank: index + 1,
        playerId: row.id,
        username: row.username,
        score: Number(row.score),
      })),
    };
  });
}
