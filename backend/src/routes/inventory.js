import { withTransaction } from "../db.js";
import { getInventory, addItem, removeItem, removeAt, moveItem, sortInventory } from "../inventory.js";

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

  // Add an item. With `partial: true`, adds what fits instead of failing
  // (used by drop pickups for stackables); `added` reports the amount.
  fastify.post("/player/:id/inventory/add", async (request, reply) => {
    const id = parseId(request, reply);
    if (id === null) return;
    const { itemId, quantity, partial } = request.body || {};

    try {
      const result = await withTransaction((client) =>
        addItem(client, id, itemId, quantity, { partial: partial === true })
      );
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

  // Move a stack (drag & drop): body { from: {containerId,x,y},
  // to: {containerId,x,y,rotated?} }. Validates placement server-side.
  fastify.post("/player/:id/inventory/move", async (request, reply) => {
    const id = parseId(request, reply);
    if (id === null) return;
    const { from, to } = request.body || {};

    try {
      const result = await withTransaction((client) => moveItem(client, id, from, to));
      const inventory = await withTransaction((client) => getInventory(client, id));
      return { ...result, inventory };
    } catch (err) {
      if (err.code === "blocked" || err.code === "out_of_bounds" || err.code === "not_found") {
        reply.code(409);
        return { error: err.code };
      }
      if (err.code === "bad_move" || err.code === "bad_slot") {
        reply.code(400);
        return { error: err.code };
      }
      throw err;
    }
  });

  // Remove the whole stack at a position (the game throws it on the ground):
  // body { containerId, x, y } → { itemId, quantity, inventory }.
  fastify.post("/player/:id/inventory/drop", async (request, reply) => {
    const id = parseId(request, reply);
    if (id === null) return;
    const { containerId, x, y } = request.body || {};

    try {
      const result = await withTransaction((client) => removeAt(client, id, { containerId, x, y }));
      const inventory = await withTransaction((client) => getInventory(client, id));
      return { ...result, inventory };
    } catch (err) {
      if (err.code === "not_found") {
        reply.code(409);
        return { error: err.code };
      }
      if (err.code === "bad_move") {
        reply.code(400);
        return { error: err.code };
      }
      throw err;
    }
  });

  // Repack the main grid (the Sort button).
  fastify.post("/player/:id/inventory/sort", async (request, reply) => {
    const id = parseId(request, reply);
    if (id === null) return;

    const result = await withTransaction((client) => sortInventory(client, id));
    const inventory = await withTransaction((client) => getInventory(client, id));
    return { ...result, inventory };
  });
}
