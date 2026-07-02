# MMO Backend

Fastify + PostgreSQL API. Source of truth for persistent player data
(HP, position, current cell, inventory). Only Roblox **servers** call it —
never clients — authenticated with a shared `X-Api-Key` header.

## Local setup

```bash
cd backend
npm install
cp .env.example .env      # then edit values
# make sure Postgres is running and DATABASE_URL points at it
npm run migrate           # creates tables
npm run dev               # starts with auto-reload on :3000
```

Quick check:

```bash
curl http://localhost:3000/health
```

## Deploy to Railway

1. Create a new Railway project, add a **PostgreSQL** plugin (sets `DATABASE_URL`).
2. Add this `backend/` folder as a service (deploy from repo, root = `backend`).
3. Set service variable `API_KEY` to a long random secret.
4. Railway runs `npm start`. Run the migration once via the Railway shell:
   `npm run migrate`.

## API

All routes except `/health` require header `X-Api-Key: <API_KEY>`.

| Method | Route                          | Body                              | Purpose                     |
|--------|--------------------------------|-----------------------------------|-----------------------------|
| GET    | `/health`                      | —                                 | Liveness (no auth)          |
| GET    | `/player/:id`                  | —                                 | Load player + inventory     |
| POST   | `/player`                      | `{ id, username }`                | Create default player       |
| POST   | `/player/:id/save`             | `{ health?, cell?, pos? }`        | Save coarse fields          |
| GET    | `/player/:id/inventory`        | —                                 | Get inventory               |
| POST   | `/player/:id/inventory/add`    | `{ itemId, quantity }`            | Add item (stacks/fills)     |
| POST   | `/player/:id/inventory/remove` | `{ itemId, quantity }`            | Remove item                 |

Item definitions live in `src/items.js` and are mirrored in the Roblox code.
