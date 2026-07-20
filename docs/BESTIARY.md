# Bestiary — kill-gated drop reveal

> Design + status doc for the bestiary feature: a persistent per-enemy kill
> counter that progressively reveals that enemy's drop table in the scout
> card (`EnemyInspectUI`) and the full `BestiaryUI` panel.
>
> Status: SHIPPED (first pass). Tier thresholds are a starting point for
> playtesting, not final — tune `shared/Bestiary.lua`'s `TIER_THRESHOLDS`,
> not the call sites.

## 1. What it is

Every enemy kill already fires `EnemyService.onKilled(lootSource, position,
killer, level)` — `QuestService` and `DropService` were already hooked into
it. `BestiaryService` adds a third hook: it bumps a persistent, per-player,
per-`lootSource` lifetime kill counter (`profile.bestiaryKills`, backend
column `bestiary_kills JSONB`).

That counter gates how much of `shared/Loot.lua`'s `Loot.TABLE`/`Loot.GEAR`
the player is shown for that enemy — not what actually rolls on kill
(`DropService` always rolls the full table regardless of what the player has
"discovered"). It's purely a display gate: scouting an enemy you've barely
fought shows `??? ` rows instead of real odds/identities.

## 2. Tiers

`shared/Bestiary.lua`:

```lua
Bestiary.TIER_THRESHOLDS = { 1, 10, 30 }
```

| Tier | Kills | Reveals |
| --- | --- | --- |
| 0 | 0 | Nothing — enemy hasn't been added to the bestiary yet. |
| 1 | 1 | Common drops (`Loot` entries tagged `tier = 1`). |
| 2 | 10 | Uncommon drops (`tier = 2`). |
| 3 | 30 | Rare drops + the `Loot.GEAR` pool (`tier = 3`). |

`Loot.lua` entries without an explicit `tier` default to 1 (always revealed
on first kill) so old data never silently disappears.

## 3. Where it lives

- **Backend** (`bestiary_kills` column, `playerService.js`): travels with
  the rest of the profile, same shape/lifecycle as `quest_progress` — loaded
  on join, saved on autosave/leave. Never resets.
- **Server** (`BestiaryService.lua`): the only thing that ever increments
  it, via `PlayerService.bumpBestiaryKill`. Republishes the whole map as
  JSON in the `BestiaryKills` player attribute immediately (cheap — a small
  table); the row itself rides the normal autosave, same as quest kill
  bumps (no forced immediate save per kill).
- **Client** (`BestiaryClient.lua`): reads that attribute, exposes
  `.kills(lootSource)` and a `.changed` signal. Both UIs read from here —
  neither needs a remote round-trip, since kills + loot tables are both
  already mirrored client-side.
- **UI**:
  - `EnemyInspectUI` — the existing click-to-inspect scout card's "Drops"
    section now gates each row by tier and shows a "Tier X/3 · N to next"
    status line.
  - `BestiaryUI` (new, top-right button / **K**) — the full list: every
    `lootSource` with known loot data (`Bestiary.knownSources`), its kill
    count, and the same tiered reveal. An enemy with 0 kills shows as
    `???` with no drop list at all — the first kill is what puts it on the
    map.

## 4. Adding a new enemy

1. Give it a `lootSource` in `EnemyService.ENEMY_DEFS` (already required for
   drops/quests to work at all).
2. Add its entries to `Loot.TABLE`/`Loot.GEAR`, each tagged `tier = 1|2|3`.
3. Add a display name to `Bestiary.NAMES` in `shared/Bestiary.lua` — it's a
   small hand-kept mirror of `ENEMY_DEFS`' `name` field, needed because
   `ENEMY_DEFS` itself is a server-only module the client can't require.

Golem and Spider already have `ENEMY_DEFS` entries but no `Loot` rows yet —
they won't appear in the bestiary until step 2 is done for them.

## 5. Open questions / future work

- Whether tier thresholds should scale per enemy (a rare golem might warrant
  lower thresholds than a common slime) instead of one global curve.
- Whether reaching tier 3 on every known enemy should itself be a tracked
  achievement/reward (ties into a future logros/achievements system).
