# MMO RPG (Roblox + Railway)

An Imperium-AO-style grid MMO on Roblox, backed by an external Railway service
(Node.js + Fastify + PostgreSQL).

See [`SPECIFICATION.md`](./SPECIFICATION.md) for the full MVP design.

## Repository layout

```
.
├── SPECIFICATION.md   # MVP design / source of truth
├── backend/           # Fastify + Postgres API (deployed to Railway)
└── roblox/            # Roblox Luau game code (added in build step 2)
```

## Build order (from the spec §10)

1. **Backend skeleton** — Fastify + Postgres on Railway  ← current
2. Roblox core — HP + inventory + persistence
3. Items & equipping (sword + axe)
4. Resource node (tree gathering)
5. Enemy & combat (slime)
6. Drop system (ground drops + pickup)
7. Second cell + border handoff

## Getting started (backend)

See [`backend/README.md`](./backend/README.md).
