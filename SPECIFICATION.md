# MMO RPG — MVP Specification

A vertical slice of an Imperium-AO-style grid MMO on Roblox, backed by an external
Railway service (Node.js + Fastify + PostgreSQL).

Goal of this MVP: prove the full loop end-to-end on a **two-cell grid** —
a player can gather, fight, collect drops, manage an inventory, take damage,
and cross a border into a second server without losing any state.

---

## 1. Architecture Overview

```
        ┌─────────────────────┐        ┌─────────────────────┐
        │  Roblox Place: Cell │        │  Roblox Place: Cell │
        │        A (0,0)      │        │        B (1,0)      │
        │  (authoritative     │        │  (authoritative     │
        │   for combat/moves) │        │   for combat/moves) │
        └──────────┬──────────┘        └──────────┬──────────┘
                   │  HTTPS (HttpService)          │
                   └───────────────┬───────────────┘
                                   ▼
                       ┌───────────────────────┐
                       │  Fastify API (Railway)│  ← source of truth
                       │   + shared-secret auth│    for persistent data
                       └───────────┬───────────┘
                                   ▼
                       ┌───────────────────────┐
                       │  PostgreSQL (Railway) │
                       └───────────────────────┘
```

**Authority split**
- **Roblox server (Luau):** authoritative for HP in combat, movement, gather/attack
  timing, enemy AI, drop spawning. The client is never trusted.
- **Backend (Fastify + Postgres):** source of truth for persistent state —
  inventory contents, HP, position, current cell. Loaded on join, saved on
  leave/teleport and periodically.

**Security:** every request from a Roblox server to the backend carries a
shared secret header (`X-Api-Key`). The backend rejects anything else. Clients
never talk to the backend directly — only Roblox servers do.

---

## 2. Player Systems

### 2.1 Health (HP)
| Field        | Value (MVP) | Notes                                  |
|--------------|-------------|----------------------------------------|
| `maxHealth`  | 100         | flat for MVP                           |
| `health`     | 0–100       | current                                |
| regen        | +1 / 2s     | only when out of combat for 5s         |
| death        | health ≤ 0  | respawn at cell spawn point, HP restored |

HP is authoritative on the Roblox server during play, persisted to backend on
save events.

### 2.2 Inventory
| Field      | Value (MVP) | Notes                          |
|------------|-------------|--------------------------------|
| capacity   | 20 slots    |                                |
| slot model | `{ itemId, quantity }` | one item type per slot |
| stacking   | per item's `maxStack`  |                        |

Client shows an inventory UI (grid of slots). All mutations happen on the
Roblox server, then persist to backend. The client only sends *intent*
(e.g. "equip slot 3"), never authoritative changes.

### 2.3 Persistence lifecycle
```
PlayerAdded         → GET /player/:id        (load HP, position, cell, inventory)
                       if 404, create default player
during play         → periodic autosave every 60s (POST /player/:id/save)
inventory change    → POST /player/:id/inventory/... (granular, immediate)
border crossing     → save, then TeleportService to the other cell
PlayerRemoving      → final save (POST /player/:id/save)
```

---

## 3. Items

Item definitions are **static config**, shared between Roblox and backend
(a hand-maintained table for MVP; served by backend later if needed).

```
Item {
  id:        string   // "sword_basic", "axe_basic", "wood", "slime_goo"
  name:      string
  type:      "weapon" | "tool" | "resource" | "misc"
  stackable: bool
  maxStack:  int
  // type-specific
  damage?:     int     // weapon: per-hit damage to enemies
  toolType?:   string  // tool: "axe" (matched against resource node requirement)
  gatherPower?:int     // tool: units gathered per successful swing
}
```

### 3.1 MVP item list
| id            | name       | type     | key stats                     |
|---------------|------------|----------|-------------------------------|
| `sword_basic` | Basic Sword| weapon   | `damage: 10`                  |
| `axe_basic`   | Basic Axe  | tool     | `toolType: "axe"`, `gatherPower: 1` |
| `wood`        | Wood       | resource | `stackable`, `maxStack: 50`   |
| `slime_goo`   | Slime Goo  | resource | `stackable`, `maxStack: 50`   |

New players start with `sword_basic` and `axe_basic` in their inventory.

### 3.2 Equipping
- Player equips a weapon/tool from inventory → it becomes a Roblox `Tool` in
  their character.
- Sword: swinging near an enemy deals `damage`.
- Axe: swinging near a resource node with matching `toolType` gathers.

---

## 4. Resource Node (Tree)

A harvestable node placed at fixed positions in each cell.

| Property      | Value (MVP)                                       |
|---------------|---------------------------------------------------|
| requires      | tool with `toolType == "axe"`                     |
| yield         | `wood` × tool's `gatherPower` per successful swing |
| capacity      | 5 units of wood                                    |
| swing time    | ~1s per gather (server-validated cooldown)         |
| depletion     | visual change to "stump" at 0                      |
| regeneration  | full respawn 60s after depletion                   |
| persistence   | **in-memory per Roblox server for MVP**            |

> Note: in-memory means a cut tree resets if the Roblox server restarts, and the
> two cells don't share tree state. Persisting world state to Postgres is a
> deliberate **post-MVP** step (see §9).

---

## 5. Enemy (Slime)

A simple hostile mob.

| Property     | Value (MVP)                                        |
|--------------|----------------------------------------------------|
| `health`     | 30                                                 |
| behavior     | idle until player in range, then walk toward + melee |
| attack       | 5 damage, ~1.5s cooldown, short range              |
| spawns       | fixed spawn points per cell                        |
| on death     | roll loot table → spawn ground drops; respawn 15s later |
| persistence  | in-memory per Roblox server (same caveat as trees) |

Enemy HP and AI are fully authoritative on the Roblox server.

---

## 6. Drop System

Two delivery styles, chosen per source:

- **Gathering (tree):** yield goes **directly to inventory** (instant, clean).
- **Enemy kill:** loot spawns as **physical drops on the ground**; player walks
  over them to pick up (classic MMO feel).

### 6.1 Loot tables
```
tree (deterministic):
  wood        100%   × gatherPower

slime (rolled on death):
  slime_goo   100%   × 1
  wood         25%   × 1     // occasional bonus
```

### 6.2 Ground drop rules
- Drop is a server-owned object with `{ itemId, quantity }`.
- Pickup: player touches drop → server validates inventory has room →
  adds item → despawns drop.
- Despawn if not picked up within 120s.

---

## 7. Two-Cell Grid & Border Handoff

Two Roblox Places: **Cell A (0,0)** and **Cell B (1,0)**, sharing an east/west
border.

```
Player reaches east edge trigger of Cell A
  1. Server: POST /player/:id/save   (HP, inventory already persisted, position, cell=B)
  2. Server: TeleportService:Teleport to Cell B place,
             teleportData = { userId, entryEdge = "west" }
  3. Cell B server, on PlayerAdded:
       - GET /player/:id  (load full state)
       - spawn character at the WEST edge spawn, offset inward
       - restore HP + inventory + equipped tool
```

**MVP simplification:** two standalone public Places is enough to prove the
handoff. Reserved-server routing for a full N×M grid is post-MVP (see §9).

**Border requirements**
- Each cell knows its own coordinate and its neighbors' Place IDs (config table).
- Entry spawn points on all four edges (only E/W wired for MVP).
- No visible state loss: HP, inventory, and equipped item identical before/after.

---

## 8. Backend API Contract (Fastify)

All routes require header `X-Api-Key: <shared secret>`.

| Method | Route                            | Purpose                              |
|--------|----------------------------------|--------------------------------------|
| GET    | `/player/:id`                    | Load player + inventory; 404 if new  |
| POST   | `/player`                        | Create default player                |
| POST   | `/player/:id/save`               | Save HP, position, cell              |
| GET    | `/player/:id/inventory`          | Get inventory                        |
| POST   | `/player/:id/inventory/add`      | Add item `{ itemId, quantity }`      |
| POST   | `/player/:id/inventory/remove`   | Remove item `{ itemId, quantity }`   |
| GET    | `/health`                        | Liveness check for Railway           |

> Granular add/remove is used for item gains/losses (safe against loss/dupe);
> `/save` handles the coarse fields (HP, position, cell). Full-inventory
> overwrite is intentionally avoided.

### 8.1 Database schema (PostgreSQL)
```sql
CREATE TABLE players (
    id           BIGINT PRIMARY KEY,          -- Roblox UserId
    username     TEXT        NOT NULL,
    health       INT         NOT NULL DEFAULT 100,
    max_health   INT         NOT NULL DEFAULT 100,
    cell         TEXT        NOT NULL DEFAULT 'A',
    pos_x        REAL        NOT NULL DEFAULT 0,
    pos_y        REAL        NOT NULL DEFAULT 0,
    pos_z        REAL        NOT NULL DEFAULT 0,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE inventory_items (
    id           BIGSERIAL PRIMARY KEY,
    player_id    BIGINT NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    slot_index   INT    NOT NULL,
    item_id      TEXT   NOT NULL,
    quantity     INT    NOT NULL CHECK (quantity > 0),
    UNIQUE (player_id, slot_index)
);
```

---

## 9. Explicitly Out of Scope (Post-MVP)

- Persisted **world state** (cut trees / dead enemies surviving server restarts,
  shared across the grid) → needs world-state tables + tick service.
- **Reserved-server** routing for a real N×M grid (MVP uses two fixed Places).
- Cross-server presence near borders (seeing players/enemies in the next cell).
- Player stats/leveling, more item types, equipment slots, trading.
- Anti-cheat logging pipeline.

---

## 10. Suggested Build Order

1. **Backend skeleton** — Fastify + Postgres on Railway; `/player` load/save +
   inventory add/remove; shared-secret auth; `/health`.
2. **Roblox core** — single cell: HP system, inventory data + UI, load-on-join /
   save-on-leave against the backend.
3. **Items & equipping** — sword + axe as equippable Tools; starter inventory.
4. **Resource node** — tree gathering with axe → wood to inventory.
5. **Enemy & combat** — slime with HP + AI; sword damages it; death.
6. **Drop system** — ground drops from slime + pickup; gather-to-inventory.
7. **Second cell + handoff** — Cell B place, border trigger, teleport with full
   state restore.

Each step is independently testable before moving on.
```