import { withTransaction } from "../db.js";
import { getInventory, addItem, removeItem, removeAt, moveItem, sortInventory, splitStack } from "../inventory.js";

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
  // `meta` marks a rolled item instance (sanitized inside addItem).
  fastify.post("/player/:id/inventory/add", async (request, reply) => {
    const id = parseId(request, reply);
    if (id === null) return;
    const { itemId, quantity, partial, meta } = request.body || {};

    try {
      const result = await withTransaction((client) =>
        addItem(client, id, itemId, quantity, { partial: partial === true, meta })
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

  // Split part of a stack off into a new stack at the first free grid spot
  // (the "Dividir" context-menu action) — nothing leaves the inventory,
  // it just becomes two stacks. body { containerId, x, y, quantity } →
  // { inventory }.
  fastify.post("/player/:id/inventory/split", async (request, reply) => {
    const id = parseId(request, reply);
    if (id === null) return;
    const { containerId, x, y, quantity } = request.body || {};

    try {
      const result = await withTransaction((client) =>
        splitStack(client, id, { containerId, x, y }, quantity)
      );
      const inventory = await withTransaction((client) => getInventory(client, id));
      return { ...result, inventory };
    } catch (err) {
      if (err.code === "not_found" || err.code === "no_room") {
        reply.code(409);
        return { error: err.code };
      }
      if (err.code === "bad_move" || err.code === "bad_quantity") {
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

  // Atomic vendor deal (docs/VENDOR_UI.md §5.2): gold delta + item removes +
  // adds settle in ONE transaction — it all lands or none of it does. The
  // Roblox server prices the deal (it's the trusted caller, same model as
  // /save gold); this route just settles it safely.
  //   body { goldDelta?, removes?: [ {itemId, quantity}            — plain stacks
  //                                | {containerId, x, y, itemId?} ], — whole row (rolled instance)
  //          adds?: [ {itemId, quantity} ] }
  //   → { ok, gold, inventory } | 409 { error: no_gold|no_items|no_space|bad_move }
  fastify.post("/player/:id/deal", async (request, reply) => {
    const id = parseId(request, reply);
    if (id === null) return;
    const body = request.body || {};
    const goldDelta = body.goldDelta ?? 0;
    const removes = body.removes ?? [];
    const adds = body.adds ?? [];

    if (
      !Number.isInteger(goldDelta) ||
      Math.abs(goldDelta) > 1_000_000_000 ||
      !Array.isArray(removes) ||
      !Array.isArray(adds) ||
      removes.length + adds.length === 0 ||
      removes.length + adds.length > 64
    ) {
      reply.code(400);
      return { error: "bad_request" };
    }

    const dealErr = (message, code) => Object.assign(new Error(message), { code });

    try {
      return await withTransaction(async (client) => {
        for (const line of removes) {
          if (line && Number.isInteger(line.x) && Number.isInteger(line.y)) {
            const removed = await removeAt(client, id, line);
            // The caller says what it expects to sell at that position; a
            // mismatch means the grid changed under the deal — abort.
            if (line.itemId !== undefined && removed.itemId !== line.itemId) {
              throw dealErr("position holds a different item", "bad_move");
            }
          } else if (line && typeof line.itemId === "string") {
            await removeItem(client, id, line.itemId, line.quantity);
          } else {
            throw dealErr("bad remove line", "bad_move");
          }
        }

        for (const line of adds) {
          if (!line || typeof line.itemId !== "string") {
            throw dealErr("bad add line", "bad_move");
          }
          await addItem(client, id, line.itemId, line.quantity);
        }

        // Relative update so concurrent writes can't lose gold; a negative
        // result throws and the whole transaction rolls back.
        const { rows } = await client.query(
          `UPDATE players SET gold = gold + $1, updated_at = now()
            WHERE id = $2 RETURNING gold`,
          [goldDelta, id]
        );
        if (rows.length === 0) throw dealErr("no such player", "bad_move");
        const gold = Number(rows[0].gold);
        if (gold < 0) throw dealErr("not enough gold", "no_gold");

        const inventory = await getInventory(client, id);
        return { ok: true, gold, inventory };
      });
    } catch (err) {
      const codes = {
        no_gold: "no_gold",
        insufficient: "no_items",
        no_room: "no_space",
        bad_move: "bad_move",
        not_found: "bad_move",
        bad_quantity: "bad_move",
        unknown_item: "bad_move",
      };
      if (codes[err.code]) {
        reply.code(409);
        return { error: codes[err.code] };
      }
      throw err;
    }
  });
}