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
  repacked into grid positions on first read. Rolled trait items carry a
  per-row `meta JSONB` ({ itemLevel, rarity?, traits }, shape-checked by
  `sanitizeMeta`): meta rows are unique INSTANCES — never top-up/merge,
  preserved verbatim by sort, skipped by generic id-based remove (vendor
  sell), returned by `removeAt` so ground drops keep the roll. Schema in
  `src/schema.sql`.
  **Item defs live in `content/items.json`** (git-tracked source of truth);
  `src/items.js` loads + validates them at boot (fails the deploy on bad
  content) and keeps the structural constants (`GRID`, `EQUIPMENT_SLOTS` —
  slot order is persisted data). `src/content.js` assembles the versioned
  payload served at `GET /content`, fetched by the Roblox `ContentService`
  at boot; the Luau mirrors (`Items.lua`, `Stores.lua`) are the fallback for
  Studio-without-HTTP and backend outages — drift gets warned at overlay
  time. **Store defs (vendor trade lists) live in `content/stores.json`**,
  validated against the item defs by `src/stores.js`. `loadPlayer`
  reconciles the starter kit (tools/weapons) on every load, so existing
  players pick up newly-added starter gear.
- **Admin dashboard** (`/admin`): `src/adminService.js` (reads + audited
  mutations), `src/adminAuth.js` (signed-cookie sessions via Node `crypto`,
  separate from the game's `X-Api-Key`), `src/routes/admin.js`, static SPA in
  `admin-web/`. Enabled only if `ADMIN_PASSWORD` is set. See
  [`docs/ADMIN_DASHBOARD.md`](docs/ADMIN_DASHBOARD.md).
- **Live admin→game push** (polling): `src/events.js` — admin mutations
  enqueue a `player_events` row (same transaction); the game drains them via
  `POST /player/events`. Kinds: `inventory` (refresh) and `stats`
  (gold/level/xp/class from the panel's Progress editor, applied live via
  `PlayerService.applyStats` + a class respec). See `AdminSyncService` below.
- Tables auto-migrate on Railway deploy via `preDeployCommand: npm run migrate`
  (see `railway.json`). Railway env vars: `DATABASE_URL` (reference to the
  Postgres plugin) + `API_KEY`; optional `ADMIN_PASSWORD` / `ADMIN_SESSION_SECRET`.

Local dev: `cd backend && npm install && npm run dev` (needs `DATABASE_URL` +
`API_KEY`; see `.env.example`).

Routes: `GET /health` (public); admin under `/admin` (own session auth);
everything else requires `X-Api-Key`: `GET /player/:id`, `POST /player`,
`POST /player/:id/save` (health, gold, cell, position, hotbar binds, client
settings),
`GET|POST /player/:id/inventory[...]` (`add` with optional `partial`,
`remove`, `move`, `sort`), `POST /player/events` (drain queued events for
online players), `GET /content` (versioned game-content defs: items, starter
kit, grid dims, equipment slots, stores).

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
`Gold` Player attribute and `addGold`/`spendGold`; also owns the persisted
client settings — whitelisted via `SETTING_VALUES`, pushed by the
`SetPlayerSettings` remote, published as the `PlayerSettings` attribute) ·
`HealthService` (HP
restore, regen, respawn) · `ManaService` (live, non-persisted mana in
`Mana`/`MaxMana` Player attributes; steady regen via the `ManaRegenAmount`
attribute; `trySpend` gates staff casts) ·
`ClassService` (classes Caballero/Arquero/Mago/Clérigo as passive stat
multipliers from `shared/Classes`; owns WalkSpeed + mana caps + the
`SwitchClass`/`RequestClassLevels` remotes; each class keeps its own
level/xp track in the profile — `PlayerService.addXp` advances only the
active class and mirrors it to the `Level`/`Xp`/`XpToNext`/`Class`
attributes, persisted via `/player/:id/save`) · `EffectService` (live buffs/debuffs; walkspeed multipliers
(class-aware) + `damageMults`/`damageTakenMult` fields fed into EnemyService's
damage hooks, replicated as `Effect_<id>` attributes holding server-clock
expiry; debuffs have diminishing returns — reapplied within 8s: 100/50/25%
duration, never cutting an active timer; slimes inflict `slow` on hit via
`EnemyService.onPlayerHit`) ·
`SpellService` (subclass spells from `shared/Spells`: validates casts behind
the `CastSpell` remote — known → target → mana → cooldown, nothing charged on
a whiff — with behaviors projectile/zone/strike/aoe/buff/taunt/summon
(familiars orbit + auto-attack; zones tick damage and/or slows — Snare Trap
is a pure-slow zone); cooldowns replicate as `SpellCd_<id>` attributes.
Knowns/passives/familiar counts derive from EQUIPMENT-earned school points
(`SynergyService.getSchoolPoints`; re-pushed via `onRecomputed` on every
inventory/Level/Class change — the class never feeds points), pushed as
`SpellsChanged` (known + newlyUnlocked + recommended); school passives ride
the damage hooks and same-stat passives SUM.
See [`docs/TRAITS_AND_SPELLS.md`](docs/TRAITS_AND_SPELLS.md)) ·
`SynergyService` (TFT-style equipment points from `shared/Traits`: sums the
trait AND school points of every non-INERT equipped piece — an item whose
`itemLevel` exceeds the active class level contributes nothing — replicates
totals as the `TraitPoints` attribute, exposes `getSchoolPoints` +
`onRecomputed` (SpellService re-derives knowns from them), and registers the
stat hooks: crit + dodge + armor (EnemyService), swing cooldown
(ToolService), buff duration (EffectService), max HP + always-on regen
(HealthService); recomputes on inventory/Level/Class changes) ·
`ToolService` (equippable Tools + `registerActivated` hook +
`registerSwingCooldownMult`; the swing cooldown gates the activation handler
too, so click spam can't out-DPS attack speed) ·
`GatheringService` (data-driven resource nodes: trees→wood, rocks→stone;
harvests burst node-themed particles and fire the `onGathered` hook — the
drop system flies the resource from the node to the player as pure show) ·
`EnemyService` (data-driven enemies: slimes, goblins + `onKilled` +
`onPlayerHit` hooks; enemies face their movement, optional `movement = "hop"`
locomotion with squash & stretch, and per-def `details` welded via
`ArtKit.weld`; per-spawn random levels scale hp/damage/xp via
`Config.Combat.mobLevel`, kills grant class XP, swings roll crits and apply
class damage multipliers by the item's `damageKind`, bow shots fly as
arrows instead of magic orbs; public combat API for spells —
`computePlayerDamage`, `enemiesNear`/`focusedTarget`/`nearestTarget`,
`dealSpellDamage`, `stun`, `slow`, `taunt` — plus `registerDamageMult`/
`registerDamageTakenMult`/`registerCritChanceBonus`/`registerDodgeChance`
hooks used by effects, subclass passives and traits (dodged hits pop
"Dodge!" and skip on-hit effects);
stunned/slowed enemies show 💫/🐌 billboard marks with remaining-duration
drain bars, slows scale walk speed and hop cadence) ·
`DropService` (loot tables → ground drops + public
`spawn(itemId, qty, pos, opts?)` + the `DropItem` remote for
drag-out-of-inventory throws; drops are magnetic — they fly to the nearest
eligible player within 10 studs — and a thrown drop ignores its owner until
they step away from it once, so others have pickup priority; stackables pick up partially
when the grid is nearly full, leftovers stay on the ground with no toast;
`GEAR_LOOT` rolls trait gear via `Traits.roll` at the mob's level ±1
(goblins ALWAYS drop a rolled piece; rolled lines are 25% school points; a
weighted rarity from `shared/Rarity` adds bonus points + extra lines),
the instance meta rides the drop part as a JSON attribute — labels show
"[Lv N]" in the tier's color — and survives pickups and throws end to end) ·
`ItemStandService` (data-driven pedestals showing a spinning item copy;
ProximityPrompt takes a copy as a normal ground drop) ·
`VendorService` (vendor NPCs placed via `VENDOR_DEFS`; the ProximityPrompt
fires `OpenStore`, trades come back through the `StoreTrade` remote and are
validated server-side — store carries the item, price side exists, player
near the vendor — then run through `PlayerService` gold + inventory so they
persist; buy refunds on a full inventory) ·
`CraftingService` (Terraria-style crafting from `shared/Recipes`: recipes
with no `station` craft anywhere, station-gated ones only near a matching
workbench placed via `WORKBENCH_DEFS` — proximity is recomputed onto each
player's `NearbyStations` attribute ~1x/second so the client can show/hide
recipes live, and re-validated server-side on the actual `CraftItem` request;
crafting removes every ingredient then adds the result, refunding the
ingredients back if the output can't fit, same shape as VendorService's
buy-refund-on-no-space) ·
`BorderService` (grid teleport
handoff) · `AdminSyncService` (polls `/player/events` every 4s → `inventory` events
refresh the inventory, `stats` events apply admin gold/level/xp/class edits
live + respec on class change; fires `Notify` either way).

**Client** (`src/client/`): `ContentSync` (applies the `ContentData` payload
to the local `Items` mirror, live on change), `HudUI` (Diablo-style health + mana orbs, an
XP bar over the hotbar, an active-effects strip, and a
10-slot hotbar: keys 1/2 mirror the paper doll's weapon/offhand, keys 3–0 are
quick binds from `HotbarBinds` — item binds equip Tools, spell binds
(`spell:<id>`) cast via `CastSpell` and render a school-colored icon with a
cooldown veil from the `SpellCd_<id>` attributes (grayed while the spell
isn't currently known — its gear unequipped); clicking an empty bind slot opens a pick-list
of known spells, and the three bind pages cycle via the button at the bar's
right end or the `X` key; HUD effect rows drain a remaining-duration bar), `SpellTrackerUI` (TFT-style tracker
mounted by `InventoryUI` to the left of the paper doll — SpellTrackerUI.start(hostFrame)
builds into whatever frame it's given, so it only exists (and is only
visible) while the inventory is open; the tooltip still gets its own
top-level ScreenGui so it can render outside the inventory panel — all
driven by the equipment-earned `TraitPoints` attribute:
school entries appear once gear gives them points (points vs next unlock —
hover → point timeline + spell rows, hover a row and press 3–0 to bind it;
sets `ClientState.spellHover` so the keypress doesn't also cast), trait
entries below them lit when their first threshold is active, hover → all
thresholds; two layouts from the options menu — compact rows or a minimal
icon-only column), `SpellsClient` (known-spell
registry from `SpellsChanged`/`RequestSpells`; auto-places newly unlocked
spells in the next free hotbar slot (page 1 first) and seeds the recommended
loadout on fresh profiles — waits on `HotbarBinds.waitReady` so it never
races the persisted binds), `InventoryUI` (grid inventory screen, `B`
key: SpellTrackerUI's trait tracker, equipment paper doll + effects panel,
Sort/gold utilities bar over the scrollable 10×30 drag & drop grid — left to
right; R rotates while
dragging, drop previews green/red, hover + 3–0 quick-binds tools/consumables,
hover + 1/2 equips a weapon/tool into weapon/offhand with the occupant
swapped back to the first free grid spot),
`HotbarBinds` (bind registry shared by the UIs, in THREE swappable pages
({ active, pages } persisted with the profile — legacy flat maps migrate to
page 1 on load); fresh profiles get axe/pickaxe seeded on keys 3/4 of
page 1),
`StoreUI` (vendor trade panel from the `OpenStore` remote: Buy/Sell tabs,
owned counts, shift-click ×5, live gold; server errors map to a status
line), `CraftUI` (crafting panel, `V` key: lists every recipe from
`shared/Recipes` the player could craft right now — station-less ones
always, station-gated ones only while `NearbyStations` says you're close
enough — with an ingredient owned/required breakdown and a Craft button
that calls the `CraftItem` remote; server is the only authority, this just
previews affordability off `InventoryUpdated`), `PlayerSettings` (client preference registry, HotbarBinds-style
lifecycle: seeded from the `PlayerSettings` attribute, changes pushed via
`SetPlayerSettings` and persisted with the profile), `SettingsUI` (options
menu behind the gear button top-right; currently the trait tracker
layout), `CharacterUI` (read-only character sheet on `C` / its top-right
button: avatar viewport, class/level/XP/gold, the summed equipment-trait
combat bonuses via `Traits.statsFor`, and every trait/school with points
tinted by its metal tier), `LevelUpUI` (celebration on the `LevelUp` remote), `DamageIndicatorUI`
(floating damage numbers from the `DamageIndicator` remote, crits pop),
`EnemyLevelUI` (recolors enemy level tags relative to the player's own
level), `GatherFeedbackUI` (harvest feedback from the `GatherFeedback`
remote), `BorderFadeUI`, `NotificationUI` (toasts from the `Notify` remote),
`ShiftLockController` (cursor lock + character faces camera; frees cursor when
inventory open), `TargetingController` (RMB focuses by equipped tool within
reach — sword→enemies, axe→trees, pickaxe→rocks), `ClientState` (shared
`aiming` / `inventoryOpen` flags), `Theme` (the Aethelgard design tokens
from `docs/UI.md` §2 — ink/stone/ember/parchment Color3 ramps, the two
serif FontFaces with a Gotham fallback guard, text sizes, orb ramps, and
the Bronze/Silver/Gold/Prismatic metal tiers + `tierFor`; rarity colors
live in `shared/Rarity`, not here), `UIKit` (widget recipes over Theme:
`stylePanel` gradient+border+forge-light shells, `titleBar`, ember
`primaryButton` / stone `ghostButton` / blood `closeButton`, hover tweens;
`addGlow`/`addShadow` wire the RadialGlow/Shadow9Slice image assets — the
shadow is a geometry-mirroring SIBLING because children always draw above
their parent — and `autoScale`/`scaleFactor` are the §9 responsiveness: a
per-element UIScale around each element's own anchor, so screen-space math
(inventory drag & drop, tooltip/picker placement) multiplies by the factor).

**Shared** (`src/shared/`): `Config` (HP/mana constants + `defaultReach`
fallback + `inventoryGrid` dims — must match backend `GRID`) · `Items`
(fallback mirror of backend defs, overlaid at boot by `Items.apply` from
`GET /content`; per-item `size` footprint, `reach`, `manaCost`, armor/ring
`slot`; plus `EQUIPMENT_SLOTS`, `sizeFor`, `slotAccepts`) · `Stores`
(fallback mirror of vendor trade lists, overlaid from `GET /content`;
`get`, `trade`, `apply`) · `Recipes` (crafting catalog — result, ingredients,
optional `station` — pure Luau data, not backend-served yet since it's
gameplay logic rather than admin-editable content; `get`/`list`) · `Classes` (class defs as passive stat
multipliers + `damageMult`; class ids mirrored in backend
`src/classes.js`) · `Spells` (subclass schools + spell defs: unlock levels,
behaviors, school passives, `hotbarPriority` recommendation order, and the
`spell:<id>` hotbar-bind + `SpellCd_<id>` attribute helpers; design + open
questions in [`docs/TRAITS_AND_SPELLS.md`](docs/TRAITS_AND_SPELLS.md)) ·
`Traits` (TFT-style trait catalog + thresholds, totals aggregation over the
equipped paper doll, the inert gate, tooltip label helpers, and the
`roll(def, itemLevel)` generator — points sum to the item level PLUS the
rolled rarity's bonus, spread over the rarity's line count from the type
pool; `entryInfo` resolves an entry's effective level/traits
with instance `meta` overriding the def's fixed values; item defs carry
`traits` points + `itemLevel` in both content mirrors) ·
`Rarity` (five-tier rarity ramp from `docs/UI.md` §5 — common/uncommon/
rare/epic/legendary with border/text/glow Color3s, weighted `roll()`,
per-tier bonus points + line counts; `forEntry`/`forDef` accessors:
instance `meta.rarity` overrides the def's optional `rarity`, absent =
common; tiers tint inventory tiles, equipment slots, tooltips and drop
labels) · `Effects`
(buff/debuff defs + the `Effect_<id>` attribute naming scheme) · `Remotes`
(RemoteEvent/Function factory) · `GridConfig` (cells keyed by PlaceId, neighbors,
border geometry, per-cell themes) · `ArtKit` (low-poly design frame: shared
flat-color palette + declarative `ArtKit.build(name, originCFrame, partSpecs)`
model builder + `ArtKit.weld(handle, specs, scale?)` for Tool/drop assemblies) ·
`ItemModels` (per-item low-poly model specs; `build(itemId)` → display Model,
`preview(viewportFrame, itemId)` → auto-framed UI thumbnail) ·
`Icons` (registry for the design-system glyphs exported to
`assets/icons_png` — white-on-transparent PNGs from `docs/UI.md` §7, preview
in `contact-sheet.html`; paste rbxassetid numbers into `Icons.ids` after
uploading, `glyphFor` maps game trait/school ids to glyph names, and every
consumer (e.g. SpellTrackerUI's hex badges) falls back to the emoji look
while an id is still 0).

### Conventions
- Systems decouple via hooks, not cross-requires:
  `ToolService.registerActivated(itemType, fn)`, `EnemyService.onKilled(fn)`,
  `PlayerService.onInventoryChanged(fn)`.
- Content is **data-driven**: add a resource node via a `NODE_DEFS` entry (+
  builder) in `GatheringService`; add an enemy via an `ENEMY_DEFS` entry in
  `EnemyService`; add an item to `backend/content/items.json` **and**
  `Items.lua` (with a `size` footprint; equipment may carry `itemLevel` +
  `traits` points — see `shared/Traits.lua` — and an optional `rarity`
  tier — see `shared/Rarity.lua`); add/reprice a store via
  `backend/content/stores.json` (+ the `Stores.lua` mirror) and place its
  vendor via a `VENDOR_DEFS` entry in `VendorService`; add an effect to
  `Effects.lua`; add a crafting recipe via a `shared/Recipes.lua` entry (+ its
  output item def if new) — gate it behind a `station` id to require a
  nearby workbench, or leave it off to craft anywhere; place a workbench via
  a `WORKBENCH_DEFS` entry in `CraftingService`.
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
- **Client UI follows the Aethelgard design system** (`docs/UI.md`, mocks in
  `docs/*.png`): colors/fonts/sizes come from `client/Theme.lua` and shells/
  buttons from `client/UIKit.lua` — no inline RGB or Gotham in UI modules.
  Sharp corners everywhere except orbs and small chips; one ember accent;
  glyph assets ride `shared/Icons.lua` (uploaded ids, emoji fallback).

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
