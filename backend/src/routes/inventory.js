import { withTransaction } from "../db.js";
import { getInventory, addItem, removeItem } from "../inventory.js";

function parseId(request, reply) {
  const id = Number(request.params.id);
  if (!Number.isInteger(id) || id <= 0) {
    reply.code(400).send({ error: "invalid player id" });
    return null;
  }
  return id;
}

export default async function inventoryRoutes(fastify) {
  // Read inventory.
  fastify.get("/player/:id/inventory", async (request, reply) => {
    const id = parseId(request, reply);
    if (id === null) return;
    const inventory = await withTransaction((client) => getInventory(client, id));
    return { inventory };
  });

  // Add an item.
  fastify.post("/player/:id/inventory/add", async (request, reply) => {
    const id = parseId(request, reply);
    if (id === null) return;
    const { itemId, quantity } = request.body || {};

    try {
      const result = await withTransaction((client) => addItem(client, id, itemId, quantity));
      const inventory = await withTransaction((client) => getInventory(client, id));
      return { ...result, inventory };
    } catch (err) {
      if (err.code === "no_room") {
        reply.code(409);
        return { error: "no_room", added: err.added };
      }
      if (err.code === "unknown_item" || err.code === "bad_quantity") {
        reply.code(400);
        return { error: err.code };
      }
      throw err;
    }
  });

  // Remove an item.
  fastify.post("/player/:id/inventory/remove", async (request, reply) => {
    const id = parseId(request, reply);
    if (id === null) return;
    const { itemId, quantity } = request.body || {};

    try {
      const result = await withTransaction((client) => removeItem(client, id, itemId, quantity));
      const inventory = await withTransaction((client) => getInventory(client, id));
      return { ...result, inventory };
    } catch (err) {
      if (err.code === "insufficient") {
        reply.code(409);
        return { error: "insufficient" };
      }
      if (err.code === "bad_quantity") {
        reply.code(400);
        return { error: err.code };
      }
      throw err;
    }
  });
}
