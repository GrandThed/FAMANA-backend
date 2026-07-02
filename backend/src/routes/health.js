import { pool } from "../db.js";

// Liveness + DB connectivity check. No auth (Railway healthcheck hits this).
export default async function healthRoutes(fastify) {
  fastify.get("/health", async (request, reply) => {
    try {
      await pool.query("SELECT 1");
      return { status: "ok", db: "up" };
    } catch (err) {
      request.log.error(err, "health check: db down");
      reply.code(503);
      return { status: "degraded", db: "down" };
    }
  });
}
