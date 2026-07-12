# Camp Tiers — persistent upgrades on top of the ephemeral Acampada

> Design doc for a per-player progression system layered on the existing
> camp (`server/CampService.lua`, `server/CampFurnitureService.lua`). The
> Acampada itself stays exactly as it is — same recipe, same 1h duration,
> same 30 min cooldown, session-scoped. Camp **tier** is a separate,
> persistent, one-time-purchase stat that changes what that Acampada is
> capable of once planted.
>
> Status: PROPOSAL — numbers are a starting point for playtesting, not final.

## 1. What stays the same vs. what's new

**Unchanged:**
- The `acampada` item, its recipe, and its cost. You still craft and plant
  it the same way, every time, regardless of tier.
- Duration (60 min) and cooldown (30 min) — tier does not touch the session
  loop, only what the session *contains*.
- The layout persistence model (`PlayerService.setCampLayout`, snapshot on
  teardown / rebuild on placement) — unchanged mechanism, just now also
  needs to carry the owner's tier so the right zone/model/furniture caps
  apply on rebuild.

**New:**
- `campTier` — a persistent int per player (0–3), stored alongside other
  player stats (gold, level, class) in the backend, loaded by `loadPlayer`
  like the rest.
- A one-time purchase per tier step, bought from an NPC vendor (see §5),
  **not** a `CraftingService` recipe — it mutates a player stat directly,
  it doesn't produce an item.
- Tier changes take effect **the next time the camp is (re)placed**, not
  live on an already-standing camp. This avoids resizing/rebuilding a zone
  and its fire model out from under furniture that's currently in use, and
  matches the existing mental model: teardown/replant is already the
  moment layouts get reloaded.

## 2. Tier table

| Tier | Cost (one-time) | `zoneSize` | Max furniture pieces | Coziness bonus range (see §3) |
|---|---|---|---|---|
| 0 (current) | — | 30 | 4 | 3 → 3 |
| 1 | `copper_ingot` × N | 40 | 6 | 3 → 5 |
| 2 | `iron_ingot` × N + `copper_ingot` × M | 50 | 8 | 4 → 7 |
| 3 | tier-3 material (TBD, once mining has a third tier) | 65 | 10 | 5 → 10 |

Exact N/M quantities: TBD in playtesting, but the intent is that each step
is a deliberate, noticeable material sink — not something that happens
incidentally while gearing up.

## 3. Coziness — the fix for "bigger zone, empty zone"

A bigger `zoneSize` without more to put in it just means more wasted grass.
Two things counter that, together:

1. **Furniture unlocks track tiers.** Each tier doesn't just raise the
   piece cap, it also unlocks new plantable pieces (see §4) — so the extra
   space always arrives bundled with something new to fill it, never
   before.
2. **Coziness bonus scales with how much you actually decorate**, not with
   tier alone. Every *cosmetic* (non-station) piece currently planted counts
   toward a coziness score, clamped to the tier's max (§2 table), which
   feeds `Config.Camp.nightRegenBonus` in place of today's flat value. A
   big empty tier-3 zone gets the same base bonus as a small empty tier-0
   one; a fully decorated tier-3 zone gets the best regen bonus in the
   game. This turns "empty space" into an active incentive to fill, not
   just a cosmetic nice-to-have.

Implementation note: cosmetic pieces are just `FURNITURE_DEFS` entries
without a `station` field (mirrors how functional pieces are defined today
— no new concept, just an unflagged subset). Coziness recalculates on
place/pickup by counting currently-planted pieces of that kind.

## 4. What each tier unlocks

- **Tier 1:** cosmetics — rug, lantern, banner. Plus **`olla_campamento`**
  (cauldron), see §6 — plantable from tier 1 onward, deliberately early so
  cooking is testable well before endgame.
- **Tier 2:** trophy mounts (rare drops — goblin ear, future boss trophies)
  as decorative pieces; decorative watchtower.
- **Tier 3:** statue, garden, upgraded campfire dressing.

All of these are new `FURNITURE_DEFS` entries, gated by a `minCampTier`
field checked in `handlePlace` alongside the existing zone/spacing/distance
checks — same validation shape, one more condition.

## 5. Purchase flow

Bought from a dedicated NPC ("camp architect") via `VendorService`, not
through `CraftingService`. Reasoning: a tier upgrade doesn't produce an
inventory item, it mutates a player stat directly, and it's a rare/large
transaction — mixing it into the recipe list would blur two very different
kinds of "spending materials" (frequent small crafts vs. a one-off
permanent upgrade).

## 6. The campfire model per tier

`CampService.buildCampModel` already builds the campfire as procedural
`ArtKit` parts (crossed logs + an `Ember` ball with a `PointLight`) — not
an imported mesh. That means per-tier variants are just alternate part-spec
tables, not new art assets to model/export:

- **Tier 0** (current): 2 crossed logs, small ember, `Range 20 / Brightness 2`.
- **Tier 1**: ring of stones around the base (boxes or reused `RockStone`
  parts, `"stone"` color), 3 logs, slightly bigger ember + light.
- **Tier 2**: iron tripod over the fire (`"steelDark"` parts, same visual
  language as the forge), sturdier stone base, ember gets a smoke
  `ParticleEmitter`. **No cauldron model baked in here** — the cauldron is
  its own craftable piece (§7), the tripod is purely dressing.
- **Tier 3**: "clan fire" — larger, carved posts/banners at the sides,
  wider/warmer light (`Range 30+`).

Refactor: pull the current inline part list out into
`CAMPFIRE_TIERS[tier] = { parts... }`, and change `buildCampModel(center)`
to `buildCampModel(center, tier)`, selecting the right table. The
perimeter (Zone/posts/rails) already scales off `zoneSize`/`ZONE_HALF`, so
it needs no changes — only the center dressing is tier-specific. The
`PointLight`-on-`"Ember"` logic stays as-is since every tier keeps a part
named `"Ember"`.

### 6.1 Reserved fire-pit radius (fixes tier-upgrade clipping)

Problem: furniture layout offsets are relative to camp center and persist
across tier upgrades (§1), so nothing is ever lost when the zone grows —
but today there's **no minimum distance enforced between furniture and the
center**, only furniture-to-furniture spacing (`FURNITURE.minSpacing`) and
zone bounds. A piece planted close to the small tier-0 fire could end up
visually inside the bigger tier-2/3 fire model after an upgrade.

Fix: reserve the **tier-3 (largest) fire footprint radius**,
`Config.Camp.firePitRadius`, as a no-place zone around the center **from
tier 0 onward** — not a per-tier radius. Add one more check in
`CampFurnitureService.handlePlace`/`handleMove`, alongside the existing
ones: reject if distance to `camp.center` is `< firePitRadius`.

Consequence: since nothing could ever be planted where a bigger fire will
one day sit, upgrading tiers never needs to move, clip, or migrate
existing furniture — there is no case to handle. Trade-off: a small
always-empty circle at the center even at tier 0, which is a minor and
intentional cost next to eliminating the clipping problem entirely.

## 7. Cooking (cauldron)

- **`olla_campamento`** — a new craftable `placeable` item, same shape as
  `cofre_campamento`/`carpa_campamento`. Plantable from **tier 1** onward
  (`minCampTier = 1` in its `FURNITURE_DEFS` entry) — deliberately early,
  not tied to tier 2, so the mechanic is testable well before endgame.
- Registers as `station = "cooking_pot"` with `CraftingService`, exactly
  like `crafting_table`/`simple_forge` register their stations today.
  Cooking is not a new system — it's `CraftingService` recipes gated behind
  a `"cooking_pot"` station, same mechanism, different name.
- **No hunger meter.** Cooked food are consumables with short-duration
  buffs, same shape as the buffs already defined in `shared/Effects.lua`
  (regen, resistance, etc.) — just sourced from cooking instead of alchemy.
- **No recipes yet.** The cauldron ships plantable and functional, but
  empty — recipes wait on ingredient sources (animals/meat) that don't
  exist yet. This mirrors how `crafting_table`/`simple_forge` also started
  empty and filled in over time; it doesn't block shipping the station.

## 8. Open questions / follow-ups

- Exact material quantities per tier (§2) — needs playtesting.
- Tier 3 material — depends on mining getting a third ore tier.
- `firePitRadius` exact value — depends on the tier-3 fire model's actual
  footprint once built.
- Cooking recipes — blocked on ingredient sources (future content, not a
  design gap).
