import { upsertPlace, recordDeploy, latestDeploy, listPlaces } from "../deploys.js";

// Deploy ledger, written by scripts/deploy-places.mjs (docs/DEPLOYMENT.md).
// Registered behind X-Api-Key: only the pipeline and Roblox servers call it.
export default async function deployRoutes(fastify) {
  // Record a deploy (and keep the place registry current from the manifest).
  fastify.post("/deploys", async (request, reply) => {
    const { placeName, placeId, universeId, versionNumber, versionType, gitCommit } =
      request.body || {};
    if (!placeName || !placeId || !universeId || !versionNumber || !versionType) {
      return reply
        .code(400)
        .send({ error: "placeName, placeId, universeId, versionNumber, versionType required" });
    }
    await upsertPlace({ placeId, universeId, name: placeName });
    await recordDeploy({ placeId, versionNumber, versionType, gitCommit });
    return { ok: true };
  });

  // Latest recorded deploy for a place (the drift check's baseline).
  fastify.get("/deploys/latest", async (request, reply) => {
    const placeId = Number(request.query.placeId);
    if (!placeId) {
      return reply.code(400).send({ error: "placeId query param required" });
    }
    return { latest: await latestDeploy(placeId) };
  });

  // Every known place + its latest deploy.
  fastify.get("/places", async () => ({ places: await listPlaces() }));
}
