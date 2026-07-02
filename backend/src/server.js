import Fastify from "fastify";
import { config } from "./config.js";
import { requireApiKey } from "./auth.js";
import healthRoutes from "./routes/health.js";
import playerRoutes from "./routes/player.js";
import inventoryRoutes from "./routes/inventory.js";
import { pool } from "./db.js";

const fastify = Fastify({
  logger: true,
});

// Health check is public (Railway probes it, no key available there).
await fastify.register(healthRoutes);

// Everything else is gated behind the shared secret.
await fastify.register(async (instance) => {
  instance.addHook("preHandler", requireApiKey);
  await instance.register(playerRoutes);
  await instance.register(inventoryRoutes);
});

// Graceful shutdown so Railway restarts/deploys don't drop the pg pool abruptly.
async function shutdown(signal) {
  fastify.log.info(`received ${signal}, shutting down`);
  await fastify.close();
  await pool.end();
  process.exit(0);
}
process.on("SIGTERM", () => shutdown("SIGTERM"));
process.on("SIGINT", () => shutdown("SIGINT"));

try {
  await fastify.listen({ port: config.port, host: "0.0.0.0" });
} catch (err) {
  fastify.log.error(err);
  process.exit(1);
}
