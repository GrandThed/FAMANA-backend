import { listClaims, getClaim, claimSettlement, releaseSettlement } from "../settlements.js";

const ERROR_STATUS = {
  in_grace: 409,
};

function parseId(value) {
  const id = Number(value);
  return Number.isInteger(id) && id > 0 ? id : null;
}

function isValidSettlementId(value) {
  return typeof value === "string" && /^[a-z0-9_]{2,64}$/.test(value);
}

export default async function settlementRoutes(fastify) {
  // All currently-owned settlements — the Roblox side polls this on join
  // (and periodically) to color the map. Neutral settlements just don't
  // appear; the client already knows the full list of ids from
  // shared/Settlements.lua.
  fastify.get("/settlements", async () => {
    const claims = await listClaims();
    return { claims };
  });

  fastify.get("/settlements/:id", async (request, reply) => {
    const id = request.params.id;
    if (!isValidSettlementId(id)) {
      reply.code(400);
      return { error: "invalid_settlement_id" };
    }
    const claim = await getClaim(id);
    return { claim };
  });

  // Called once, server-side, the moment a guardian/challenger dies —
  // guildId is whoever's server-side damage tracker had the top individual
  // contributor. killerId is optional context for the capture log.
  fastify.post("/settlements/:id/claim", async (request, reply) => {
    const id = request.params.id;
    if (!isValidSettlementId(id)) {
      reply.code(400);
      return { error: "invalid_settlement_id" };
    }
    const { guildId, killerId, graceSeconds } = request.body || {};
    const gId = parseId(guildId);
    if (gId === null) {
      reply.code(400);
      return { error: "invalid_guild_id" };
    }
    const kId = killerId === undefined ? null : parseId(killerId);

    try {
      const claim = await claimSettlement(id, gId, kId, graceSeconds || undefined);
      return { claim };
    } catch (err) {
      const status = ERROR_STATUS[err.code];
      if (status) {
        reply.code(status);
        return { error: err.code, graceUntil: err.graceUntil };
      }
      throw err;
    }
  });

  fastify.post("/settlements/:id/release", async (request, reply) => {
    const id = request.params.id;
    if (!isValidSettlementId(id)) {
      reply.code(400);
      return { error: "invalid_settlement_id" };
    }
    await releaseSettlement(id);
    return { ok: true };
  });
}
