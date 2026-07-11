# Map authoring & place deployment

How FAMANA places get their worlds, and how code reaches every place. This is
the workflow for building maps **visually in Studio** while keeping all
mechanics in git — and deploying to any number of places with one command.

## 1. The mental model

A Roblox **place** = the 3D world (Workspace) + the code. In this repo those
have different owners:

| What | Lives in | Reaches a place via |
| --- | --- | --- |
| Mechanics (all Luau code) | `roblox/src/` | Rojo (serve while authoring, build when deploying) |
| The map (terrain, buildings, layout) | `roblox/maps/<name>.rbxm` | Authored in Studio, exported to the repo |
| Place settings (HTTP on, spawn, name) | `roblox/<name>.project.json` | Baked in at build time |
| Which places exist | `roblox/places.json` | Read by the deploy script |

Historically this project had **no maps at all**: every tree, rock, enemy,
vendor and workbench spawns at runtime from hardcoded positions in the
service defs (`NODE_DEFS.spots`, `ENEMY_DEFS.spots`, `VENDOR_DEFS`, …). That
still works and remains the fallback for any place without an authored map —
which is also why a bare Studio baseplate playtest keeps working.

## 2. Markers: how a map places gameplay objects

An authored map is decoration; gameplay objects (harvestable trees, enemies,
vendors…) are still **built by the services at boot** so all behavior stays in
code. The map just says *where*, using **marker parts**:

1. Insert a plain `Part` where the object should stand (any size — make it
   `Anchored`). Rotate it to face where the object should look (its front is
   **-Z**, i.e. the face the blue axis arrow points away from).
2. Tag it: select the part → Properties → **Tags** section → `+` → type the
   tag. One tag per marker.
3. At server boot the service reads the marker's position/rotation, destroys
   the part, and builds the real object there. Markers are never visible in
   game.

| Tag | Places | Key comes from |
| --- | --- | --- |
| `Node_tree`, `Node_rock`, `Node_iron_rock`, `Node_hardwood_tree` | Gathering node | `NODE_DEFS` key (GatheringService) |
| `Enemy_slime`, `Enemy_goblin` | Enemy spawn point | `ENEMY_DEFS` key (EnemyService) |
| `Vendor_general_goods` | Vendor NPC | `VENDOR_DEFS` storeId (VendorService) |
| `Workbench_crafting_table`, `Workbench_simple_forge` | Crafting station | `WORKBENCH_DEFS` station (CraftingService) |
| `ItemStand_<itemId>` | Item display stand | any item id with a model |

The switch between markers and the hardcoded fallback is the **`Map` folder**:
if `Workspace.Map` exists, services spawn ONLY from markers (`shared/MapMarkers`);
if not, they use the def positions. Boot output tells you what happened — a
typo'd tag prints `markers match no def` and a def with zero markers prints
`none spawned`, so check the output window first when something's missing.

Ground height is handled for you: services raycast down at the marker's X/Z,
so a marker floating above a hill still builds on the ground.

## 3. Authoring a map in Studio, step by step

1. Open the place in Studio, run `rojo serve` in `roblox/` and connect the
   plugin (this syncs the code, exactly like before — `default.project.json`
   doesn't touch Workspace, so nothing you build gets overwritten).
2. Create a **Folder named `Map`** directly under Workspace. Build the entire
   map inside it — ground, buildings, decoration, and all marker parts.
   Keeping everything in one folder is what makes step 4 a single export.
3. Playtest as usual. The moment the `Map` folder exists, markers drive all
   spawning — if you haven't placed `Node_tree` markers yet, no trees.
4. Export: right-click the `Map` folder → **Save to File…** → save as
   `roblox/maps/<name>.rbxm` (e.g. `cellA.rbxm`). This is the ONLY manual
   sync step, needed only when the map itself changed.
5. Commit the `.rbxm` (gitignore has an exception for `roblox/maps/`) and
   deploy (§4). Publishing from Studio (File → Publish) still works too for
   the one place you have open.

## 4. Deploying

The full pipeline lives in [`DEPLOYMENT.md`](DEPLOYMENT.md). The short
version: **commit the exported map (and any code) and push to `main`** —
GitHub Actions builds every place from the repo and publishes it via Open
Cloud. Manual runs still work
(`node scripts/deploy-places.mjs [--draft] [--restart] [names…]`), with the
Open Cloud key in the repo-root `.env`.

Live servers keep the old version until they empty; migrate them explicitly
with `--restart` (or the workflow's `restart: true` input). Adding a new
place is a 5-step checklist in `DEPLOYMENT.md`.

## 5. Gotchas

- **A deploy replaces the whole place.** Map work that was never exported to
  `roblox/maps/` is overwritten. Export before you deploy.
- **Close the place in Studio before deploying it.** An open Studio session
  holds a lock on the place and uploads bounce with `409: Server is busy`
  (the script retries a few times, but a held lock outlasts them).
- **`Secret.lua` must exist locally** — the script refuses to deploy without
  it, because the built place couldn't reach the backend.
- **Place-level settings live in the project files now.** The per-place
  projects force `HttpEnabled = true` and carry the fallback Baseplate +
  SpawnLocation. Things configured only in Studio that aren't in the project
  json or the map (e.g. Lighting tweaks) reset on deploy — either put them in
  the map folder (works for instances) or add `$properties` to the project.
- **`rojo serve` keeps using `default.project.json`.** The per-place projects
  are for building only; serving one would make Rojo fight you over the
  Baseplate/Map in Studio.
- The fallback Baseplate in the project files sits under any authored map.
  Once a map brings its own ground, delete the `Baseplate` node from that
  place's project json.
