# Per-Item Stats (Armor & Evasion)

> Spec for the system behind the mock tooltip's **"Armor +14  Evasion +2"**
> line (`docs/UI.md` §6.5, `docs/full_inventory.png`). Today defense comes
> ONLY from trait thresholds (Bastion→armor, Evasion→dodge, Brawler→HP);
> items themselves carry no stats besides weapon `damage`/`reach`/`manaCost`.
> This adds a small per-item stat block that scales with item level and
> rarity — without touching the database or the instance-meta shape.

## 1. Goal & scope

- Equipment (armor now; rings/offhand later) carries **base stats** that
  contribute directly to the wearer while equipped, alongside the existing
  trait synergies.
- Stats **scale with the instance's item level and rarity**, so a Lv 9 Epic
  Leather Tunic beats a Lv 2 Common one — making rolled drops of the same
  base item meaningfully different beyond their trait lines.
- **MVP stat catalog: `armor` and `evasion`** — both already have server
  hooks, so no new combat plumbing is needed. `hp`/`regen`/`manaRegen` are
  phase 2 (they need HealthService/ManaService changes for flat values).

Out of scope (mock elements with no backing system): resistances,
attribute allocation, weapon defensive stats.

## 2. Design

### 2.1 Stat catalog (MVP)

| Stat | Unit | Applies via |
|---|---|---|
| `armor` | flat; damage taken × 100/(100+armor) | the armor total SynergyService already feeds EnemyService |
| `evasion` | percent points of dodge (2 = +2%) | the dodge-chance hook SynergyService already registers |

Display units are player-friendly integers ("Armor +14", "Evasion +2");
evasion converts to a fraction (÷100) only where it joins the dodge roll.

### 2.2 Scaling — the core formula

```
effective(stat) = round(base × levelMult × rarityStatMult)
levelMult       = 1 + 0.15 × (itemLevel − 1)
```

- `base` comes from the def (`stats` field, §3). Items without an
  `itemLevel` (plain tools/resources) use levelMult = 1.
- `rarityStatMult` is a new per-tier field in `shared/Rarity.lua`:

| Tier | statMult |
|---|---|
| common | 1.00 |
| uncommon | 1.06 |
| rare | 1.12 |
| epic | 1.22 |
| legendary | 1.35 |

- Rolled instances read `itemLevel`/`rarity` from their `meta` (same
  precedence as `Traits.entryInfo` / `Rarity.forEntry`); fixed defs read
  their own `itemLevel`/`rarity` fields.

**Mock parity check** — Leather Tunic base `{ armor = 8, evasion = 1 }` at
Lv 5 Rare: armor = round(8 × 1.6 × 1.12) = **14**, evasion =
round(1 × 1.6 × 1.12) = **2**. Exactly the mock's tooltip.

### 2.3 Rules (consistent with traits)

- **Paper doll only**: stats count only while the entry sits in the
  `equipment` container.
- **Inert gate applies**: an item whose effective level exceeds the ACTIVE
  class level contributes NO stats (same red-square rule as traits — one
  gate, one mental model).
- **Stacking**: item stats and trait-threshold stats SUM. Item armor adds
  to Bastion armor; item evasion adds to the Evasion trait's dodge.
- **Soft cap (tuning guard)**: total dodge (trait + item) clamps at 40%
  server-side so stacked evasion can't approach unhittable. Armor needs no
  cap (its formula has diminishing returns built in).

### 2.4 Balance intent (first pass)

At equal level, a full set's summed item armor should land near ONE
Bastion tier (~25–40 armor at mid levels) — items are the steady baseline,
trait thresholds are the build-defining spikes. Numbers in §6 aim there
and are expected to be tuned.

## 3. Data model — no schema, no meta changes

Item defs gain an optional `stats` map in **both content mirrors**
(`backend/content/items.json` + `roblox/src/shared/Items.lua`):

```json
"chest_leather": {
  "...": "...",
  "stats": { "armor": 8, "evasion": 1 }
}
```

- Effective values are **derived at read time** from `def.stats` +
  `meta.itemLevel` + `meta.rarity`. Nothing new is persisted: rolled
  instances keep the existing `meta = { itemLevel, rarity?, traits }`, so
  `sanitizeMeta`, `schema.sql`, sort/move/merge rules and the drop
  attribute pipeline are all untouched.
- `backend/src/items.js` validates the shape at boot (fail the deploy on
  bad content): `stats` optional; keys from the known catalog
  (`armor`, `evasion`); values positive integers ≤ 500.
- Content payload (`GET /content`) carries the field automatically — defs
  are served wholesale.

## 4. New shared module — `roblox/src/shared/ItemStats.lua`

Single source of the formula, used by server combat and client UI alike.
Requires only `Rarity` (and reads defs the callers pass in) — no cycles.

```lua
ItemStats.KEYS   = { "armor", "evasion" }            -- display order
ItemStats.forEntry(entry, def) -> { armor?, evasion? } | nil
  -- effective (scaled) stats of an inventory entry; nil when the def has
  -- no stats. Reads meta.itemLevel/meta.rarity with def fallbacks.
ItemStats.totalsFor(inventory, level) -> { armor = n, evasion = n }
  -- sums forEntry over the equipment container, skipping INERT pieces
  -- (mirrors Traits.totalsFor's shape and gate).
ItemStats.label(key, value) -> "Armor +14"           -- tooltip/detail line
```

## 5. Server & client changes

### SynergyService (the only combat-side change)

It already walks the paper doll on every inventory/Level/Class change and
owns the armor + dodge hooks. Extend `recompute(player)`:

- `local itemTotals = ItemStats.totalsFor(profile.inventory, level)`
- Add `itemTotals.armor` into the armor total it feeds EnemyService.
- Add `itemTotals.evasion / 100` into the dodge fraction (then clamp the
  combined dodge at 0.40).
- Publish the totals as a new `EquipStats` attribute (JSON), next to
  `TraitPoints` — the Character window reads it without needing the
  inventory.

No changes to EnemyService/HealthService — the hooks already exist.

### Client (read-only)

- **InventoryUI tooltip**: prepend `ItemStats.forEntry` values to the §6.5
  stat line — `"Armor +14  ·  Evasion +2"` before damage/reach/stack.
- **StoreUI detail pane**: same line under the rarity label (defs only, so
  levelMult uses the def's `itemLevel`).
- **CharacterUI**: a "Defense" pair in the Vitals section — total Armor and
  Dodge% from the `EquipStats` attribute (plus the trait-granted portion it
  already lists via `Traits.statsFor`).

## 6. Starting content (demonstrative, to be tuned)

Base values at levelMult 1; fixed defs also get scaled by their own
`itemLevel`/`rarity` (e.g. Bastion Helm below shows ~16 armor in-game).

| Item | stats | Notes |
|---|---|---|
| helmet_leather | armor 5 | |
| chest_leather | armor 8, evasion 1 | mock item — Lv 5 Rare roll = 14/2 |
| gloves_leather | armor 4 | |
| legs_leather | armor 6 | |
| boots_leather | armor 4, evasion 1 | |
| helmet_bastion (Lv 5, rare) | armor 9 | reads ≈16 in-game |
| chest_colossus (Lv 8, epic) | armor 12 | reads ≈30 in-game |
| boots_evader (Lv 9, epic) | armor 4, evasion 3 | reads ≈11 / 8 in-game |

Weapons, tools, resources and emblems get no `stats`. Rings stay pure
trait/school carriers until phase 2 (`hp` on Ring of Vitality, `manaRegen`
on Ring of Focus are the natural first uses).

## 7. Implementation checklist

1. `shared/Rarity.lua` — add `statMult` per tier.
2. `shared/ItemStats.lua` — new module (formula + totals + labels).
3. Content: `stats` in `backend/content/items.json` + `Items.lua` mirror
   (§6 table); validation in `backend/src/items.js`.
4. `server/SynergyService.lua` — fold item totals into the armor/dodge
   hooks, clamp dodge, publish `EquipStats`.
5. Client: tooltip line (InventoryUI), store detail line (StoreUI),
   Defense rows (CharacterUI).
6. Docs: CLAUDE.md (shared module + convention line), TRAITS.md status
   note (items now carry scaled base stats alongside trait points).

## 8. Verification

- `node -e "import('./src/items.js')"` — content validation passes.
- `luau-analyze` on the touched Luau files.
- Manual, in Studio vs a slime:
  1. Note damage taken naked → equip the leather set → damage drops per
     the armor formula; unequip → returns.
  2. Roll drops (goblins) → tooltip shows scaled Armor/Evasion matching
     `round(base × levelMult × statMult)` for the label's Lv/tier.
  3. Switch to a Lv 1 class with a Lv 5 piece equipped → INERT: tooltip
     warns, EquipStats totals drop, damage taken rises.
  4. Character window Defense row equals tooltip sums of equipped pieces.

## 9. Open questions

1. **Evasion units** — percent points as proposed ("Evasion +2" = +2%
   dodge), or an abstract rating with its own curve? (Proposal: percent
   points; simplest to read and to sum with the trait.)
2. **Dodge soft cap** — is 40% total the right ceiling?
3. **Scaling slope** — 15% per item level compounds well with the bonus
   trait points from rarity; steeper (20%) makes leveled drops more
   exciting but inflates armor fast. (Proposal: ship 15%, tune.)
4. **Phase 2 stats** — flat `hp` (HealthService), `manaRegen`
   (ManaService): worth speccing now or after armor/evasion prove out?
