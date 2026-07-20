import { loadPlayer, createPlayer, savePlayer } from "../playerService.js";
import { drainEvents } from "../events.js";

// Validates and parses a Roblox UserId path param.
function parseId(request, reply) {
  const id = Number(request.params.id);
  if (!Number.isInteger(id) || id <= 0) {
    reply.code(400).send({ error: "invalid player id" });
    return null;
  }
  return id;
}

export default async function playerRoutes(fastify) {
  // Drain pending events for the given online players. Called by the game's
  // poll loop; returns and removes events so each is delivered once.
  fastify.post("/player/events", async (request) => {
    const { userIds } = request.body || {};
    const events = await drainEvents(userIds || []);
    return { events };
  });

  // Load full player state.
  fastify.get("/player/:id", async (request, reply) => {
    const id = parseId(request, reply);
    if (id === null) return;

    const player = await loadPlayer(id);
    if (!player) {
      reply.code(404);
      return { error: "not_found" };
    }
    return player;
  });

  // Create a default player (starter items). Idempotent.
  fastify.post("/player", async (request, reply) => {
    const { id, username } = request.body || {};
    const numId = Number(id);
    if (!Number.isInteger(numId) || numId <= 0) {
      reply.code(400);
      return { error: "invalid player id" };
    }
    if (typeof username !== "string" || username.length === 0) {
      reply.code(400);
      return { error: "username required" };
    }
    const player = await createPlayer(numId, username);
    reply.code(201);
    return player;
  });

  // Save coarse fields (health, gold, level, xp, class + per-class levels,
  // hotbar binds, client settings, quest progress, cell, position, camp
  // layout/tier).
  fastify.post("/player/:id/save", async (request, reply) => {
    const id = parseId(request, reply);
    if (id === null) return;

    const { health, gold, level, xp, currentClass, classLevels, hotbarBinds, settings, questProgress, trackedQuestId, cell, position, campLayout, campTier, bestiaryKills, stats, achievementsUnlocked } = request.body || {};
    const ok = await savePlayer(id, { health, gold, level, xp, currentClass, classLevels, hotbarBinds, settings, questProgress, trackedQuestId, cell, position, campLayout, campTier, bestiaryKills, stats, achievementsUnlocked });
    if (!ok) {
      reply.code(404);
      return { error: "not_found" };
    }
    return { saved: true };
  });
}