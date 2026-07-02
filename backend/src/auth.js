import { config } from "./config.js";

// Fastify preHandler that rejects any request without the shared secret.
// Registered globally; /health opts out (see server.js).
export function requireApiKey(request, reply, done) {
  const provided = request.headers["x-api-key"];
  if (provided !== config.apiKey) {
    reply.code(401).send({ error: "unauthorized" });
    return;
  }
  done();
}
