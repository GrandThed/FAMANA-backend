# Traits v2 — Convex power curve + full catalog

> Design review expanding the traits board (`docs/all_traits/traits.png`) on
> top of the shipped system (`shared/Traits.lua`, `shared/Rarity.lua`,
> `SynergyService`). Companion to [`TRAITS_AND_SPELLS.md`](TRAITS_AND_SPELLS.md);
> this doc is the v2 proposal, that one stays the record of what shipped.
>
> Status 2026-07-10: PROPOSAL — numbers are concrete so they can be dropped
> into `Traits.lua` as-is, but everything here is up for a tuning pass.
> Decisions needed from Benja are collected in §8.
> The consolidated final writeout of every trait/school/innate + synergy
> map + gap list lives in [`TRAITS_CATALOG.md`](TRAITS_CATALOG.md).

## 1. Goals

1. **Concentration beats diversification.** The value a trait pays per point
   must GROW with the points invested, so a build with 2–3 deep traits beats
   one with 7 shallow ones. Today's ladders do the opposite (front-loaded:
   Lynx Eye pays 10%/pt at 1 point, ~3%/pt at 16).
2. **Three families, abilities in exactly two** (simplified 2026-07-10).
   *Passive traits* — as many as the game needs, 100% stat budget, never a
   button. *Schools* (the 12 subclasses) and *class innates* (4) are the
   ONLY ability carriers — schools carry **4 abilities each**, innates
   **5** — paying ~60% of the pure passive budget for them. Everything
   balances around that frame (§4).
3. **Ship the whole board.** Everything on the traits board gets a def:
   the missing offensives (Arcane Practice, Physical Training, Inferno),
   the utility diamonds (Life Essence, mana regen, Roll, Dash), Guardian,
   plus the two boxes that were still empty — gathering traits and
   class-connected traits.
4. **Hand items count only in hand** (decided 2026-07-10). Armor and rings
   always contribute; the weapon/offhand/tool contributes its traits ONLY
   while actually wielded. Pull out your pickaxe and the sword's crit lines
   switch off while the pickaxe's mining lines switch on. This bans
   stat-stick tools, makes gathering builds coexist with combat builds on
   one doll for free, and weapon-swapping becomes a real stance choice.

## 2. The curve

One rule for every ladder: **value(p) ≈ V_cap × (p / p_cap)^1.5**, hand-rounded
so that value-per-point strictly increases tier over tier. γ = 1.5 is the
tuning knob (γ = 1 is today's roughly-linear feel; γ = 2 is very punishing
early).

Consequences, stated honestly:

- Early tiers get **nerfed** (Lynx Eye tier 1: 10% → 2%). A fresh player's
  first trait line is a taste, not a power spike — their spike is the school
  line's level-1 spell, which stays at 1 point.
- The mid game is where the incentive lives: 10 points in ONE trait (+24%
  crit) now clearly beats 5+5 in two (+8% +8%).
- Top tiers keep or beat today's values, so deep investment feels spectacular.

### The point economy (why caps must also move)

10 equipment slots, item points = item level + a small rarity bonus (§6). Theoretical
totals: **~100 points at class level 10, ~200 at level 20**. Today's ladders
cap at 17–22 points — at endgame a player could max SIX traits at once and
"low volume of traits" stops being a choice.

Proposal: give the core % traits **prestige tiers at 25 and 30** (below), so
maxing one trait costs ~2–3 dedicated slots of perfect gear and an endgame
doll realistically supports 3–4 deep traits + change. Deeper caps are also
what make stacking same-trait legendaries (§6) worth the hunt.

## 3. Catalog v2 — retuned ladders (pure passives)

> The full, current catalog (incl. the 2026-07-10 additions Executioner /
> Leech / Retribution, the Control stat, and the gathering reserves) lives
> in [`TRAITS_CATALOG.md`](TRAITS_CATALOG.md) — this section is the original
> retune rationale.

Existing six, same threshold points, new values (old values in parens):

| Trait | Ladder |
|---|---|
| **Lynx Eye** (crit) | 1→**2%** (10) · 4→**8%** (20) · 7→**15%** (30) · 10→**24%** (35) · 13→**35%** (40) · 16→**48%** (50) · 20→**68%** (65) · 22→**80%** (90) · ✦26→**95%** |
| **Agile Hands** (attack speed) | 1→**2%** · 4→**8%** · 7→**15%** · 10→**24%** · 13→**35%** · 16→**48%** · 20→**68%** · 22→**85%** · ✦26→**110%** |
| **Perseverance** (ability duration) | 3→**8%** (5) · 7→**20%** (10) · 11→**40%** (15) — board wanted 15/30/50; this middles it |
| **Brawler** (max HP + regen) | 2→**6%, 1%/s** (20, 2) · 5→**16%, 2%/s** (35, 2) · 8→**30%, 3%/s** (50, 4) · 11→**48%, 4%/s** (65, 4) · 16→**80%, 6%/s** (80, 6) · 22→**120%, 8%/s** (100, 6) |
| **Bastion** (armor) | 2→**8** (10) · 5→**22** (25) · 8→**40** (40) · 11→**66** (80) · 16→**110** (110) · ✦22→**170** |
| **Evasion** (dodge) | 5→**3%** (5) · 7→**5%** (7) · 9→**7%** (9) · 11→**10%** (11) · 13→**13%** (13) · 15→**17%** (15) · 17→**22%** (17) |

✦ = new prestige tier (needs cap-tuning blessing, §8.3).

New pure passives from the board:

| Trait | Ladder |
|---|---|
| **Arcane Practice** (+% magic damage) | 1→2% · 4→8% · 7→15% · 10→24% · 13→35% · 16→48% · 20→68% · 22→90% |
| **Physical Training** (+% physical damage) | same ladder |
| **Inferno** (+% debuff duration you inflict: stuns, slows, zone snares) | 3→10% · 7→25% · 11→50% |
| **Life Essence** (+% healing you RECEIVE — potions, cleric spells; regen excluded so it doesn't double-dip Brawler) | 2→6% · 5→16% · 8→28% · 11→44% · 16→70% |
| **Clarity** (+% mana regen — board diamond had no numbers) | 2→10% · 5→25% · 8→45% · 11→70% · 16→110% |

Stacking rule (already the doc'd recommendation): trait damage %, school
passive %, and class multipliers each sum additively WITHIN their category,
then the categories multiply.

## 4. The three families — abilities live in exactly two places (simplified 2026-07-10)

| Family | Count | Abilities | Passive budget | Points source |
|---|---|---|---|---|
| **Passive traits** | open-ended (§3 + below) | none, ever | 100% | equipment (+ rebirth perm) |
| **Schools** (subclasses = the endgame builds) | 12 — 3 per class | **4 each** at 1/10/20/30 | ~60% | equipment (+ perm) |
| **Innates** | 4 — 1 per class | **5 each** at levels 1/5/12/20/30 | ~60% (incl. gathering identity) | class level (+ rebirth cap) |

What the frame buys:

- **Button count is bounded by construction.** A single-build character
  fields 9 abilities (4 school + 5 innate); a Twin-Soul dual-kit endgame
  fields up to 18 (8 school + 5 innate + the Twin Soul innate's 4 sub-30
  abilities) — comfortably inside the hotbar's 24 bind slots (8 × 3 pages).
- **Passive traits are cheap to add** — a ladder + a stat hook, never a
  button — so "as many as we need" can't creep complexity. New abilities
  only ever arrive by touching a school or an innate: rare and deliberate.
- Budget rule unchanged: an ability carrier's passive line pays **~60% of a
  pure passive** at equal points.

**Schools — 4 abilities each (1/10/20/30).** The shipped three (1/10/20)
plus a NEW **apex ability at 30** (supersedes the "ultimate ascends" idea —
a 4th spell is simpler to read than upgraded copies; Invoker's 3rd familiar
arrives with its apex, *Legion*). Passives = 0.6 × the pure value at equal
points on the rebalanced grid 1/5/10/15/20/✦25/✦30 — full per-school
ladders in TRAITS_CATALOG §2 (template: 1/6/16/29/44/✦62/✦81). The base
kit still completes at 20 — one L20 legendary school-main = full kit, the
deliberate chase-item moment — while the apex REQUIRES assembly (school
side lines on other pieces, or rebirth perm points): endgame/rebirth
content by construction.

**Reclassified into the passive family** (procs don't count as abilities —
no button, no exception):

- **Guardian** — ally = party member (PartyService; no proc solo).
  2→8% chance to shield the hit ally (15% their max HP, 4s) · 5→15% ·
  8→+aura: party in 20 studs +6 armor · 11→proc 25% · 16→aura +12 ·
  22→shields also heal 10% missing HP.
- **Prospector / Woodsman** — yield/double-harvest/no-deplete procs only;
  the Ore/Timber Sense ACTIVES ARE CUT (if they return, it's as innate
  ability candidates). Roll rules unchanged: keyed by tool kind (a
  pickaxe's main line is always Prospector, an axe's always Woodsman — a
  pickaxe with Woodsman can't roll), side lines from a small "handling"
  pool (Agile Hands, Evasion), and per the hand rule (§1.4) tool traits
  only work while the tool is out. Gear gathering traits AMPLIFY the
  class-innate gathering identity (§5) additively — a Knight in
  Prospector gear is the server's best miner; an Archer can still gear
  into mining without the innate edge. Later, once content exists:
  Herbalist (sickle + herb nodes), Alchemist (potions), Plunderer (mob
  drops).
- **Roll / Dash** — no longer standalone traits. The board's movement
  actives become candidates for the innate ability slots (a dash reads
  Precision/archer, a defensive iframe-roll reads Valor/knight); Scout's
  Sprint already covers part of this space.

## 5. Class traits connected to level (CONFIRMED 2026-07-10 — revises 2026-07-06)

The standing rule is "the class NEVER feeds points; all points come from
equipment". The ask — *class-specific traits connected to the level* — needs
one carve-out, and it can be surgical:

> Each class owns ONE innate trait. Its points **equal the active class
> level**, it can never roll on gear, and gear can never add to it. Every
> other trait stays 100% equipment-fed.

Structure (simplified 2026-07-10): **5 abilities each at levels
1/5/12/20/30**, plus convex passive tiers every ~5 levels. Level 1 puts a
class button in every fresh character's hands from minute one (alongside
the starter weapon's first spell); 1/5/12 are the class's bread-and-butter
actives — this settles the board's old open question "do classes without a
subclass get abilities or only stats?": abilities. Level 20 is the
capstone below; level 30 is its ASCENDED version,
rebirth-only (the innate cap extension, REBIRTH_AND_BUILDS §3 — this is
what Apotheosis's "ascended capstones" refers to). The 1/5/12 ability
designs are an open pass — Roll/Dash are candidates (§4). Each innate ALSO carries
the class's **gathering identity** (decided 2026-07-10) — the line that
differentiates how each class harvests the world, scaling up the same
ladder:

| Class | Innate trait | Passive flavor | Gathering identity | Capstone idea (lv 20; lv 30 = ascended) |
|---|---|---|---|---|
| Knight | **Valor** | armor + phys % (small, convex) | +% yield from natural resources — wood, stone, iron | *Second Wind* — once per fight, heal 25% at low HP |
| Archer | **Precision** | attack speed + move speed | +% drops from enemies (materials, consumables, gold — NEVER equipment, so the rolled-gear economy stays intact) | *Double Nock* — next shot fires twice |
| Mage | **Attunement** | magic % + mana regen | potion-crafting bonuses — chance for a double brew / ingredients refunded | *Overflow* — next cast is free |
| Cleric | **Devotion** | healing % + HP regen | +% yield when gathering herbs | *Sanctuary* — brief no-damage zone |

Gathering ladder sketch (same for all four, on their own resource): 5→+10% ·
10→+25% · 15→+45% · 20→+70% · 25→+100% (rebirth range: 30→+150%).

Content prerequisites the gathering identities create: **iron nodes** and
**herb nodes** are new `NODE_DEFS` in GatheringService (herbs probably
per-cell flora via WorldService theming), and **potion recipes** need to
exist in `shared/Recipes.lua` for Attunement to have something to boost
(CraftingService gains a per-player output/refund hook, same shape as the
gathering yield hook).

Why it's worth the carve-out: leveling currently pays only base-stat
multipliers and the inert gate; an innate trait makes the level visible in
the same tracker UI as everything else, and it's the cleanest reading of
"traits specific to the class connected to the level". Cost: one exception
to a clean invariant, and SynergyService must merge a non-equipment source
into totals (small: `totalsFor` gains a `+ innate` step keyed off the
Class/Level attributes it already recomputes on).

If the carve-out is refused, the fallback is class-BIASED gear pools
(knight-y items roll defensive traits more often) — no invariant break, but
much weaker as a "class identity" feature.

## 6. Rarity = concentration (DECIDED 2026-07-10)

Today: rarity adds bonus points AND spreads the roll over MORE lines
(legendary = always 3). Under a convex curve, spreading is a tax — a
legendary that splits 25 points three ways is often WORSE than a common
that puts 20 in one trait. Earlier candidates (invert line counts /
front-load harder / "main line + rarity side lines") are superseded by:

> **Rarity ramps BOTH axes: concentration and bonus points.** The main
> line is capped at a rarity-scaled share of the ITEM LEVEL — only a
> legendary's main line reaches the full item level — and the rarity's
> bonus points ride along as side lines. Total points = item level + bonus;
> the main line never exceeds the item level. **Bonus scales with level**
> (rebalanced 2026-07-10, replaces flat +0/1/2/3/5): uncommon +5% · rare
> +10% · epic +15% · legendary +25% of item level, rounded up, min 1 — a
> L20 legendary still gets +5, but a L4 legendary no longer nearly doubles
> itself.

Focus ramp (lines clamped by the point budget at low levels; `mainShare` =
the main line's cap as a fraction of item level):

| Rarity | Bonus (% of level, ceil, min 1) | Lines | mainShare | Level-10 sword example | Effective (rebalanced Lynx ladder) |
|---|---|---|---|---|---|
| Common | +0 | 4 | ≤40% | Lynx 4 / Agile 3 / Pers 2 / Evasion 1 | +2% + splash |
| Uncommon | +5% (L10: +1) | 3 | ≤60% | Lynx 6 / Agile 4 / Pers 1 | +8% + splash |
| Rare | +10% (L10: +1) | 2–3 | ≤70% | Lynx 7 / Agile 4 | +8% |
| Epic | +15% (L10: +2) | 2–3 | ≤90% | Lynx 9 / Agile 2 / Pers 1 | +15% + splash |
| Legendary | +25% (L10: +3) | 2–3 | 100% | **Lynx 10** / Agile 2 / Pers 1 | **+15%** (2 from tier 12) + splash |

Why this wins:

- **The curve powers the rarity gap** (concentration: same-ish points, ~3×
  effective value from shape) **and the bonus keeps rarity meaningful on a
  second axis** — even where the ladder steps are coarse, a legendary is
  visibly richer. The two axes never fight: higher rarity is strictly
  better on both.
- **Commons make generalists, legendaries make specialists.** A full common
  doll is a low-tier jack-of-all-trades; chasing rarity IS chasing a build.
- **Chase items self-define.** BiS = max-level legendary in your primary
  trait; prestige tiers (26/30) can't be reached by one item, so endgame
  hunts "legendary + a deep same-trait rare/epic" — multi-item assembly.
- **Loot gets interesting.** A concentrated level-8 legendary (tier 7)
  beats a smeared level-12 common for a focused build — item level stops
  being strictly dominant.

Point economy note: bonus creep is small — theoretical max climbs from 200
to 250 (10 slots, all legendary L20), realistic dolls ~210–220. The §2 cap
sizing already assumed this range.

Known cost (accepted): common drops carry mostly sub-threshold splash — the
early game feels traits faintly, which is the motivation engine; if it tests
badly, soften γ rather than inflating common rolls.

Implementation: `Rarity.defs` keeps `bonusPoints` and swaps `minLines`/
`maxLines` for `lines` + `mainShare`; `Traits.roll` rolls the main line up
to `mainShare × itemLevel` (exactly `itemLevel` for legendary) and spreads
the remainder + bonus over the side lines. Persistence shape
`{ itemLevel, rarity, traits }` unchanged; `sanitizeMeta`'s 4-line cap fits
the common's max exactly.

## 7. Implementation map (by phase)

Nothing here needs a backend migration — points are what persist; values are
derived at read time. `sanitizeMeta` already accepts arbitrary trait ids
(≤32 chars, ≤4 lines, ≤30 pts/line).

0. ~~**English pass (do first)**~~ — SHIPPED 2026-07-11: ids renamed with
   read-time LEGACY_IDS aliases (backend `inventory.js` for item ids +
   `meta.traits` keys, `HotbarBinds` for `spell:<id>` binds); class/passive
   display names translated. Quest/party/UI text sweep still pending.
1. ~~**Curve retune**~~ — SHIPPED 2026-07-11: `Traits.lua` ladders on the
   standard grid + all nine school passives retuned incl. ✦25/✦30.
2. ~~**New pure passives**~~ — SHIPPED 2026-07-11: all eight
   (physical_training, arcane_practice, executioner, leech, inferno,
   life_essence, retribution, clarity) + ranger school passives (sniper
   physical, scout attackSpeed, trapper control). New hooks:
   `EnemyService.registerCritDamageBonus/Lifesteal/Reflect/
   DebuffDurationBonus/SlowPotency` (+ enemy-side CC diminishing returns,
   100/50/25% in an 8s window), `HealthService.registerHealReceivedMult`,
   `ManaService.registerRegenMult`. Super-crit overflow (Lynx past 100%)
   is NOT yet implemented — unreachable until prestige stacking exists.
3. ~~**Rarity = concentration**~~ — SHIPPED 2026-07-11: `Rarity.defs` now
   carries `bonusPercent`/`mainShare`/`lines`, `Traits.roll` rolls the main
   line at the tier's share of item level (legendary = the full level) with
   the level-scaled bonus as side lines; sides never out-grow the main.
4. ~~**Gathering traits + class identities**~~ — SHIPPED 2026-07-11:
   Prospector/Woodsman defs (pickaxe/axe forced main lines, handling side
   pool, no schools on tools); GatheringService gained yield / double /
   no-deplete hooks (bonuses are FREE yield — only the base amount wears
   the node); the class identities live on ClassPassives from level 5
   (Knight gatherYield — wood/stone/ore all exist already — Archer
   mobDrops via DropService's quantity hook that skips gear, Mage
   craftDouble via CraftingService's double-craft hook gated on
   `recipe.potion`, Cleric herbYield gated on the `sickle` toolType).
   The **hand rule** shipped with it: ToolService tracks the held Tool
   (`getHeldItemId`/`onHeldChanged`), `Traits.totalsFor` counts the doll's
   weapon/offhand only while nothing else is wielded and swaps in the held
   grid tool's lines (first matching entry, inert-gated), SynergyService
   recomputes on equip/unequip. Still content-pending: herb nodes +
   sickle, potion recipes (hooks no-op until they exist).
5. **Guardian** — temp-HP shields on players (HealthService) + party-scoped
   aura; PartyService provides "ally".
6. **Abilities pass** — the 12 school apex spells (threshold 30) + the 20
   innate abilities; any movement actives (dash/iframe-roll) need the
   movement/iframe system (new service + an input decision, §8.6). Biggest
   lift, last.
7. **Class innate traits** — confirmed (§5); SynergyService merges innate
   points into totals on the Level/Class recompute it already does.

## 8. Decisions needed

1. ~~**Class innate traits** — approve the one-exception carve-out in §5?~~
   **CONFIRMED 2026-07-10** — innates are in; they extend past 20 via the
   rebirth system, see [`REBIRTH_AND_BUILDS.md`](REBIRTH_AND_BUILDS.md).
2. ~~**Rarity lines**~~ — DECIDED 2026-07-10: rarity ramps concentration AND
   bonus points; only a legendary's main line reaches the full item level
   (§6).
3. **Prestige tiers** — extend core ladders to 26/30 as in §3? (Sized against
   the 10-slot point economy; without them, endgame maxes ~6 traits at once.)
4. ~~**Life Essence semantics**~~ — DECIDED 2026-07-10: healing RECEIVED
   (potions + ally spells + on-hit heals; passive regen excluded). See
   TRAITS_CATALOG §5.
5. ~~**Perseverance/Inferno magnitude**~~ — DECIDED 2026-07-10: re-derived
   on the rebalanced grid (depth-16: Perseverance →40%, Inferno →50% with
   an enemy-side diminishing-returns prerequisite). TRAITS_CATALOG §5.7.
6. **Movement-ability input** (innate dash/iframe-roll, §4) — dedicated key
   (Space-double-tap? Q?) vs a hotbar bind like spells.
7. **γ = 1.5** — comfortable with how hard the early tiers get squeezed
   (Lynx Eye 1pt: 10% → 2%)? γ = 1.3 is the gentler variant.
8. **School↔class binding** — schools are NOT class-native (confirmed
   2026-07-06: `classIds` is flavor, any class can use any school's gear;
   the class steers via stat multipliers, the innate, and mana). Keep fully
   soft (recommended — hard gates make school-main legendaries dead loot
   for 3/4 of finders), or gate only ASCENSION (26/30) behind the native
   class so mastery stays class identity while dabbling stays open?
