# CLAUDE.md

Guidance for Claude Code (and humans) working in this repo.

## What this is

**FAMANA** — an Imperium-AO-style **grid MMO** on Roblox, backed by an external
service on Railway. The world is split into grid cells; each cell is a separate
Roblox **Place** and players teleport across cell borders with their full state
intact.

- **Roblox client/server (Luau)** in [`roblox/`](roblox/) — authoritative for
  real-time gameplay (combat, movement, gathering).
- **Backend (Node.js + Fastify + PostgreSQL)** in [`backend/`](backend/),
  deployed to Railway — the **source of truth for persistent data** (HP, gold,
  inventory, position, current cell). Roblox talks to it over HttpService; the
  Roblox client never talks to it directly.

Full design lives in [`SPECIFICATION.md`](SPECIFICATION.md). Build history is in
the git log; the MVP was built in 7 steps (see that file's §10).

## Architecture at a glance

```
Roblox Place (Cell A)  ─┐                        ┌─ PostgreSQL
Roblox Place (Cell B)  ─┼─ HTTPS (X-Api-Key) ─►  Fastify API  ─┤  (Railway)
   (same code, differ  ─┘   server-only            (Railway)   └─
    by game.PlaceId)
```

- **Authority split:** Roblox server owns live gameplay; the backend owns
  persistence. Inventory changes write through to the backend immediately;
  HP/position autosave every 60s and on leave/teleport.
- **Security:** every backend request carries `X-Api-Key`. Clients never call
  the backend — only Roblox servers do.

## Backend (`backend/`)

Fastify + `pg` (raw SQL, ESM). Live at
`https://famana-backend-production.up.railway.app`.

- Entry: [`src/server.js`](backend/src/server.js). Auth hook in `src/auth.js`.
- Persistence: `src/playerService.js`, `src/inventory.js` — a **grid
  inventory**: every stack sits at `(x, y)` in a container (`main` = the
  10×30 grid where items occupy a `size` W×H footprint, optionally `rotated`;
  `equipment` = paper-doll slots, x = `EQUIPMENT_SLOTS` index). Transactional
  add (first-fit + stack-filling, `partial` option for pickups), remove,
  `moveItem` (drag & drop verb: placement/overlap/slot validation + stack
  merge), `sortInventory` (repack). Legacy flat `slot_index` rows are
  repacked into grid positions on first read. Schema in `src/schema.sql`.
  **Item defs live in `content/items.json`** (git-tracked source of truth);
  `src/items.js` loads + validates them at boot (fails the deploy on bad
  content) and keeps the structural constants (`GRID`, `EQUIPMENT_SLOTS` —
  slot order is persisted data). `src/content.js` assembles the versioned
  payload served at `GET /content`, fetched by the Roblox `ContentService`
  at boot; the Luau mirror (`Items.lua`) is the fallback for Studio-without-
  HTTP and backend outages — drift gets warned at overlay time. `loadPlayer`
  reconciles the starter kit (tools/weapons) on every load, so existing
  players pick up newly-added starter gear.
- **Admin dashboard** (`/admin`): `src/adminService.js` (reads + audited
  mutations), `src/adminAuth.js` (signed-cookie sessions via Node `crypto`,
  separate from the game's `X-Api-Key`), `src/routes/admin.js`, static SPA in
  `admin-web/`. Enabled only if `ADMIN_PASSWORD` is set. See
  [`docs/ADMIN_DASHBOARD.md`](docs/ADMIN_DASHBOARD.md).
- **Live admin→game push** (polling): `src/events.js` — admin item mutations
  enqueue a `player_events` row (same transaction); the game drains them via
  `POST /player/events`. See the Roblox `AdminSyncService` below.
- Tables auto-migrate on Railway deploy via `preDeployCommand: npm run migrate`
  (see `railway.json`). Railway env vars: `DATABASE_URL` (reference to the
  Postgres plugin) + `API_KEY`; optional `ADMIN_PASSWORD` / `ADMIN_SESSION_SECRET`.

Local dev: `cd backend && npm install && npm run dev` (needs `DATABASE_URL` +
`API_KEY`; see `.env.example`).

Routes: `GET /health` (public); admin under `/admin` (own session auth);
everything else requires `X-Api-Key`: `GET /player/:id`, `POST /player`,
`POST /player/:id/save` (health, gold, cell, position),
`GET|POST /player/:id/inventory[...]` (`add` with optional `partial`,
`remove`, `move`, `sort`), `POST /player/events` (drain queued events for
online players), `GET /content` (versioned game-content defs: items, starter
kit, grid dims, equipment slots).

## Roblox (`roblox/`) — Rojo + Rokit

Synced into Studio with **Rojo 7.7.0** (pinned in `rokit.toml`). Structure maps
`src/shared` → `ReplicatedStorage.Shared`, `src/server` → `ServerScriptService`,
`src/client` → `StarterPlayerScripts` (see `default.project.json`).

Run: `cd roblox && rojo serve`, connect via the Rojo Studio plugin.

**Server services** (`src/server/`, started by `init.server.lua`):
`ContentService` (fetches `GET /content` at boot with retries, overlays the
defs via `Items.apply`, publishes the payload to clients through the
`ContentData` StringValue in ReplicatedStorage; on failure the game runs on
the Luau mirror) ·
`WorldService` (per-cell theming) · `PlayerService` (load/save/cache +
`onInventoryChanged` hook + `refreshInventory` + grid `moveItem`/
`sortInventory` behind `MoveItem`/`SortInventory` remotes + live gold with a
`Gold` Player attribute and `addGold`/`spendGold`) · `HealthService` (HP
restore, regen, respawn) · `ManaService` (live, non-persisted mana in
`Mana`/`MaxMana` Player attributes; steady regen; `trySpend` gates staff
casts) · `EffectService` (live buffs/debuffs; walkspeed multipliers,
replicated as `Effect_<id>` attributes holding server-clock expiry; slimes
inflict `slow` on hit via `EnemyService.onPlayerHit`) ·
`ToolService` (equippable Tools + `registerActivated` hook) ·
`GatheringService` (data-driven resource nodes: trees→wood, rocks→stone;
harvests burst node-themed particles and fire the `onGathered` hook — the
drop system flies the resource from the node to the player as pure show) ·
`EnemyService` (data-driven enemies: slimes, goblins + `onKilled` +
`onPlayerHit` hooks; enemies face their movement, optional `movement = "hop"`
locomotion with squash & stretch, and per-def `details` welded via
`ArtKit.weld`) ·
`DropService` (loot tables → ground drops + public
`spawn(itemId, qty, pos, opts?)` + the `DropItem` remote for
drag-out-of-inventory throws; drops are magnetic — they fly to the nearest
eligible player within 10 studs — and a thrown drop ignores its owner until
they step away from it once, so others have pickup priority; stackables pick up partially
when the grid is nearly full, leftovers stay on the ground with no toast) ·
`ItemStandService` (data-driven pedestals showing a spinning item copy;
ProximityPrompt takes a copy as a normal ground drop) ·
`BorderService` (grid teleport
handoff) · `AdminSyncService` (polls `/player/events` every 4s → refreshes
inventory + fires `Notify` for live admin edits).

**Client** (`src/client/`): `ContentSync` (applies the `ContentData` payload
to the local `Items` mirror, live on change), `HudUI` (Diablo-style health + mana orbs and a
10-slot hotbar: keys 1/2 mirror the paper doll's weapon/offhand, keys 3–0 are
quick binds from `HotbarBinds`), `InventoryUI` (grid inventory screen, `B`
key: equipment paper doll + effects panel on the left, Sort/gold utilities
bar over the scrollable 10×30 drag & drop grid on the right; R rotates while
dragging, drop previews green/red, hover + 3–0 quick-binds tools/consumables),
`HotbarBinds` (session-only bind registry shared by the two UIs),
`BorderFadeUI`, `NotificationUI` (toasts from the `Notify` remote),
`ShiftLockController` (cursor lock + character faces camera; frees cursor when
inventory open), `TargetingController` (RMB focuses by equipped tool within
reach — sword→enemies, axe→trees, pickaxe→rocks), `ClientState` (shared
`aiming` / `inventoryOpen` flags).

**Shared** (`src/shared/`): `Config` (HP/mana constants + `defaultReach`
fallback + `inventoryGrid` dims — must match backend `GRID`) · `Items`
(fallback mirror of backend defs, overlaid at boot by `Items.apply` from
`GET /content`; per-item `size` footprint, `reach`, `manaCost`, armor/ring
`slot`; plus `EQUIPMENT_SLOTS`, `sizeFor`, `slotAccepts`) · `Effects`
(buff/debuff defs + the `Effect_<id>` attribute naming scheme) · `Remotes`
(RemoteEvent/Function factory) · `GridConfig` (cells keyed by PlaceId, neighbors,
border geometry, per-cell themes) · `ArtKit` (low-poly design frame: shared
flat-color palette + declarative `ArtKit.build(name, originCFrame, partSpecs)`
model builder + `ArtKit.weld(handle, specs, scale?)` for Tool/drop assemblies) ·
`ItemModels` (per-item low-poly model specs; `build(itemId)` → display Model,
`preview(viewportFrame, itemId)` → auto-framed UI thumbnail).

### Conventions
- Systems decouple via hooks, not cross-requires:
  `ToolService.registerActivated(itemType, fn)`, `EnemyService.onKilled(fn)`,
  `PlayerService.onInventoryChanged(fn)`.
- Content is **data-driven**: add a resource node via a `NODE_DEFS` entry (+
  builder) in `GatheringService`; add an enemy via an `ENEMY_DEFS` entry in
  `EnemyService`; add an item to `backend/content/items.json` **and**
  `Items.lua` (with a `size` footprint); add an effect to `Effects.lua`.
- New gameplay that grants items must go through `PlayerService.addItem/
  removeItem` so it persists and the UI/tools stay in sync. Inventory
  placement is validated **backend-side only** — the client just previews
  fits and asks via the `MoveItem` remote.
- Tool/weapon reach is a per-item `reach` stat on the def; server combat/gather
  and client focus all read that single value (`Config.defaultReach` is only a
  fallback). Ranged weapons (`weaponType = "ranged"`) require a focused target.
- Item ids/defs must match between `backend/content/items.json` and
  `roblox/src/shared/Items.lua`.
- **World assets are low-poly, built via `ArtKit`** (`src/shared/ArtKit.lua`):
  a few chunky rotated blocks, flat colors from `ArtKit.Palette` (no inline RGB
  in builders), SmoothPlastic everywhere. Build with `ArtKit.build` relative to
  an origin CFrame. The gameplay anchor is the model's `PrimaryPart` and carries
  the `Depleted` attribute — client targeting relies on both.
- **Every item gets a model in `ItemModels.lua`** (spec list; first spec = the
  grip/primary part at the origin, equippables stand along +Y). One catalog
  drives held Tools (ToolService), inventory + hotbar thumbnails (ViewportFrame
  via `ItemModels.preview`), and miniature ground drops (DropService). A part
  named `Orb` gets a PointLight when built as a Tool.

## Critical gotchas

- **`Secret.lua` is gitignored.** `roblox/src/server/Secret.lua` returns the
  backend `API_KEY`. It's required for backend calls but never committed. A
  fresh clone must recreate it.
- **Enable HTTP in Studio** (Game Settings → Security → Allow HTTP Requests) or
  the game silently falls back to a temporary, non-persisted profile.
- **Teleport needs a published game.** `TeleportService` does nothing in Studio
  playtest — the border handoff can only be tested live. In Studio the border
  just fades out and back in (fail-safe). See
  [`docs/BORDER_TESTING.md`](docs/BORDER_TESTING.md).
- **PlaceIds** for the two cells live in `GridConfig.cells`; both places must be
  published with the same, filled-in config.
- **World state is in-memory per server** (trees/enemies reset on restart, not
  shared across the grid). Persisting it is deliberately post-MVP.

## Git / workflow

- Default branch `main`, remote `github.com/GrandThed/FAMANA-backend`.
- Commit at logical checkpoints; end commit messages with the Co-Authored-By
  trailer.
- Don't commit secrets (`.env`, `Secret.lua`) — both are gitignored.
