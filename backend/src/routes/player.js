import { loadPlayer, createPlayer, savePlayer } from "../playerService.js";

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

  // Save coarse fields (health, cell, position).
  fastify.post("/player/:id/save", async (request, reply) => {
    const id = parseId(request, reply);
    if (id === null) return;

    const { health, cell, position } = request.body || {};
    const ok = await savePlayer(id, { health, cell, position });
    if (!ok) {
      reply.code(404);
      return { error: "not_found" };
    }
    return { saved: true };
  });
}
