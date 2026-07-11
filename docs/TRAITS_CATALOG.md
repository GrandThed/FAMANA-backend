# Trait Catalog — canonical v2 reference

> The final writeout of every trait, school and innate under the v2 rules
> ([`TRAITS_V2.md`](TRAITS_V2.md): convex curve, rarity = concentration +
> bonus, hand rule, three families) and the rebirth economy
> ([`REBIRTH_AND_BUILDS.md`](REBIRTH_AND_BUILDS.md)). Names marked
> *(proposed)* are new designs filling empty slots — everything else is
> board-sourced or already shipped. Numbers are tuning-ready, not sacred.
>
> Family rules (TRAITS_V2 §4): passive traits never carry a button; schools
> carry 4 abilities (1/10/20/30); innates carry 5 (levels 1/5/12/20/30).
> Ability carriers pay ~60% of a pure passive's stat budget.
>
> **REBALANCED 2026-07-10** — board-inherited numbers are gone; every ladder
> is re-derived from the final framework:
> - **One standard grid: 2 / 5 / 8 / 12 / 16 / 20 / ✦25 / ✦30** (✦ =
>   prestige, unreachable from a single item — needs stacking, rarity bonus
>   or rebirth perm points). Schools sample at 1/5/10/15/20/✦25/✦30,
>   innates at levels 5/10/15/20/25/30.
> - **Values from the curve**: v(p) = V_max × (p / p_max)^1.5, rounded.
> - **Depth classes cap each trait where its stat stays safe**: depth 30
>   (scaling cores — incl. crit, whose overflow past 100% becomes SUPER
>   CRIT chance, §5.7) · depth 25 (dodge, crit damage, lifesteal) · depth
>   20 (party) · depth 16 (narrow/dangerous/utility).
> - **Hybrid discounts**: schools = 0.6 × pure value at equal points;
>   innates = 0.2 × pure (they're free — level-fed — and carry 5 abilities
>   + the gathering identity).
> - **Rarity bonus scales with level** (replaces flat +0/1/2/3/5):
>   uncommon +5% · rare +10% · epic +15% · legendary +25% of item level,
>   rounded up, min 1 — a L20 legendary still gets +5, but a L4 legendary
>   no longer nearly doubles itself.

## 1. Passive traits (17 live + 3 ready, content-gated)

**Offensive — weapon roll pool** (side lines on any slot via rings):

| Trait | Stat (depth) | Ladder (points → value) |
|---|---|---|
| **Physical Training** | physical damage (30) | 2→2% · 5→9% · 8→18% · 12→34% · 16→52% · 20→73% · ✦25→102% · ✦30→135% |
| **Arcane Practice** | magic damage (30) | same ladder as Physical Training |
| **Agile Hands** | attack speed (30) | 2→2% · 5→8% · 8→16% · 12→30% · 16→47% · 20→65% · ✦25→91% · ✦30→120% |
| **Lynx Eye** | crit chance (30 — overflow past 100% becomes super-crit chance, §5.7) | 2→2% · 5→8% · 8→15% · 12→28% · 16→43% · 20→61% · ✦25→85% · ✦30→110% |
| **Executioner** | crit damage, base crits are 2× (25) | 2→+3% · 5→+11% · 8→+22% · 12→+40% · 16→+61% · 20→+86% · ✦25→+120% |
| **Leech** | lifesteal on weapon hits, not spells (25) | 2→1% · 5→3% · 8→5% · 12→10% · 16→15% · 20→21% · ✦25→30% |
| **Perseverance** | ability/buff duration (16 — cd-bounded, stops early) | 2→2% · 5→7% · 8→14% · 12→26% · 16→40% |
| **Inferno** | debuff duration you inflict (16 — ships WITH enemy-side diminishing returns) | 2→2% · 5→9% · 8→18% · 12→32% · 16→50% |

**Defensive — armor roll pool:**

| Trait | Stat (depth) | Ladder |
|---|---|---|
| **Brawler** | max HP + regen (30) | 2→2%, 0.5%/s · 5→9%, 1 · 8→18%, 1.5 · 12→33%, 2.5 · 16→50%, 3.5 · 20→71%, 5 · ✦25→99%, 6.5 · ✦30→130%, 8 |
| **Bastion** | armor (30) | 2→3 · 5→12 · 8→25 · 12→45 · 16→70 · 20→98 · ✦25→137 · ✦30→180 |
| **Evasion** | dodge (25 — hard cap) | 5→2% · 8→4% · 12→8% · 16→13% · 20→18% · ✦25→25% |
| **Guardian** | party shields — procs, no button (20) | 2→2% shield proc (15% ally max HP, 4s) · 5→6% · 8→13% + aura +6 armor (20 studs) · 12→23% + aura +8 · 16→36% + aura +12 · 20→50% + aura +16, shields also heal 10% missing HP |
| **Life Essence** | healing received (16) — DECIDED: incoming heals (potions, ally spells, on-hit heals); passive regen excluded, no Brawler/Devotion double-dip | 2→2% · 5→10% · 8→19% · 12→36% · 16→55% |
| **Retribution** | reflect % of melee damage taken (16) | 2→2% · 5→10% · 8→19% · 12→36% · 16→55% |

**Utility — ring pool (Clarity) / tool-kind mains (gathering):**

| Trait | Stat (depth) | Ladder |
|---|---|---|
| **Clarity** | mana regen (16) | 2→5% · 5→19% · 8→39% · 12→71% · 16→110% |
| **Prospector** | mining — pickaxe main line ONLY (16) | 2→+4% stone/iron · 5→+17% · 8→+35%, 10% double-harvest · 12→+65% · 16→+100%, 25% no-deplete |
| **Woodsman** | logging — axe main line ONLY (16) | mirror of Prospector for wood |

**Ready, content-gated** (defs written, activate when their content ships):

| Trait | Stat | Ladder | Waits on |
|---|---|---|---|
| **Herbalist** | herb yield (sickle main line, depth 16) | mirror of Prospector | herb nodes + sickle tool |
| **Alchemist** | potion crafting (ring pool, depth 16) | 2→8% double brew · 5→17%, 10% ingredient refund · 8→30%, 15% · 12→50%, 22% · 16→75%, 30% | potion recipes |
| **Plunderer** | mob-drop quantity, never equipment (ring pool, depth 16) | 2→+3% · 5→+11% · 8→+23% · 12→+42% · 16→+65% | the DropService qty hook |

Roll pools recap: weapons draw the offensive EIGHT (25% chance a line is a
school instead); armor draws the defensive SIX; rings draw anything (incl.
Clarity, and Alchemist/Plunderer once live); tools main-line their own kind
+ "handling" sides (Agile Hands, Evasion).

## 2. Schools — 12 subclasses, 4 abilities each (1/10/20/30)

Passives = 0.6 × the pure-trait value at equal points (rebalanced grid
1/5/10/15/20/✦25/✦30):

- **Damage/healing template** (Pyromancer, Berserker, Sniper, Light Priest):
  1→1% · 5→6% · 10→16% · 15→29% · 20→44% · ✦25→62% · ✦30→81%
- **Quieter variants** (~85%: Arcanist, Justicar, Holy Avenger, Oracle):
  1→1% · 5→5% · 10→14% · 15→25% · 20→38% · ✦25→52% · ✦30→69%
- **Invoker** (lowest — familiars carry it): 1/4/11/20/31/✦43/✦57
- **Sentinel** (armor): 1→1 · 5→7 · 10→21 · 15→38 · 20→59 · ✦25→82 · ✦30→108
- **Trapper** (control — slow strength): 1/6/16/28/44/✦61/✦80
- **Scout** (attack speed, 0.6 × Agile Hands): 1/5/14/26/39/✦55/✦72

Base kit completes at 20; the 30-apex requires assembly or rebirth perm
points. Apex spells are *(proposed)*; first-pass numbers in §5.

| School | Passive | 1 | 10 | 20 | 30 — apex |
|---|---|---|---|---|---|
| **Pyromancer** | magic | Fireball | Flame Wall | Supernova | *Meteor* — huge delayed AoE |
| **Arcanist** | magic | Arcane Missile | Arcane Rain | Arcane Storm | *Singularity* — pull + burst (the board's "mass confusion?" note) |
| **Invoker** | magic | Summon Familiar | 2nd familiar | Grand Familiar | *Legion* — 3rd familiar + empower window (supersedes "3rd at 26") |
| **Berserker** | physical | Battle Cry | Savage Strike | Frenzy | *Bloodbath* — kills during Frenzy extend it + heal |
| **Sentinel** | armor | Provoke | Steel Loyalty | Bulwark | *Aegis* — party-wide damage-absorb shield |
| **Justicar** | physical | Stunning Strike | Judgment | Verdict | *Tribunal* — mass mark; judged enemies take amplified damage |
| **Sniper** | physical (SHIPPED 2026-07-11) | Deadeye Shot | *Charged Shot* (board) | *Overwatch* (merges two board designs — aim mode: damage scales with distance, next shot is a guaranteed crit) | *One Shot, One Kill* — guaranteed-crit execute at range |
| **Trapper** | **control** (SHIPPED 2026-07-11 — slow-potency hook in EnemyService, rides the same enemy-side DR as Inferno) | Snare Trap | *Explosive Net* (board) | *Minefield* (board) | *Master Trapper* — 3 armed traps at once (board's Yordle traps) |
| **Scout** | attack speed (SHIPPED 2026-07-11 — sums with Agile Hands in the swing-cooldown hook) | Sprint | *Fan of Arrows* (board) | *Infinite Vision* (board: see enemies through walls) | *Arrow Rain* (board, GP-ult scale) |
| **Light Priest** | healing | Healing Touch | Blessing | Revival | *Miracle* — instant party-wide heal burst |
| **Holy Avenger** | magic | Holy Strike | Reprisal | Divine Judgment | *Crusade* — party lifesteal + damage window |
| **Oracle** | healing | Purify | Spirit Link | Intervention | *Prophecy* — no party member can die for ~3s |

The three ranger schools' 10/20 spells existed on the spells board but were
never written into `Spells.lua` (only their level-1s shipped) — this table
is now their def source. The three ranger passives did not exist AT ALL;
stats proposed above (Scout's attack-speed passive needs no new hook;
a Trapper "CC potency" stat would need one — physical is the safe default).

## 3. Innates — 4 classes, 5 abilities each (levels 1/5/12/20/30)

Points = active class level; rebirth extends the cap 20 → 30 (+1 per 5
rebirths). Passives = 0.2 × pure value (innates are free and carry 5
abilities + the gathering identity), sampled at levels 5/10/15/20/25/30;
gathering identity is the exception — it's the class's PRIMARY claim on its
niche, so it runs hot (V30 = 150%, above the gear traits' 100%). The 1/5/12
abilities come straight off the spells board's per-class lists (the old
"classes without subclass" designs — they were never shipped; this is
their home). Level 30 = ascended capstone, rebirth-only.

> **Waves A+B1 shipped 2026-07-11** (via `Spells.innates`,
> class-level-gated): all 1/5/12 slots are castable — Shield Bash, Iron
> Roll, Defensive Stance, True Shot, Swift Step, Hunter's Mark, Energy
> Bolt, Mana Shield, Overcharge, Minor Prayer, Minor Blessing. Movement =
> client-executed dash + server iframes; shields = the Guardian-phase
> temp-HP pool. Still pending: Sacred Circle (cleric 12 — ally zones) and
> all 20/30 capstones. Minor Prayer shipped as an instant heal (the HoT
> version waits on a heal-over-time effect).

**Valor (Knight)** — armor 2/7/13/20/27/36 + phys 2/5/9/15/20/27% ·
gathering: natural resources +10/29/53/82/114/150%
| Lv | Ability |
|---|---|
| 1 | **Shield Bash** (board) — shield strike, pushes enemies back; reflects projectiles |
| 5 | *Iron Roll* (proposed — the board's Roll lands here: iframe roll) |
| 12 | **Defensive Stance** (board) — take less frontal damage, deal less |
| 20 | **Second Wind** — once per fight, heal 25% at low HP |
| 30 | *Second Wind Ascended* — heal 50%, brief invulnerability, and nearby enemies are staggered + briefly taunted (the board's area-stun ultimate lives on here) |

**Precision (Archer)** — attack speed 2/5/8/13/18/24% + move 1/2/4/6/9/12% ·
gathering: mob drops (never equipment) +10/29/53/82/114/150%
| Lv | Ability |
|---|---|
| 1 | **True Shot** (board) — bonus-crit shot vs wounded targets |
| 5 | **Swift Step** (board — the Dash lands here: dash + brief move speed) |
| 12 | **Hunter's Mark** (board) — mark a target; your hits on it crit far harder |
| 20 | **Double Nock** — next shot fires twice |
| 30 | *Double Nock Ascended* — next THREE shots fire twice |

**Attunement (Mage)** — magic 2/5/9/15/20/27% + mana regen 4/11/19/30/42/55% ·
gathering: potion crafting (double brew / refund) 10/29/53/82/114/150%
| Lv | Ability |
|---|---|
| 1 | **Energy Bolt** (board) — cheap spammable projectile |
| 5 | **Mana Shield** (board) — translucent screen that absorbs damage |
| 12 | **Overcharge** (board) — all magic abilities deal bonus damage for a window |
| 20 | **Overflow** — next cast is free |
| 30 | *Overflow Ascended* — next cast is free, doubled, and off-cooldown |

**Devotion (Cleric)** — healing 2/5/9/15/20/27% + HP regen 0.3/0.8/1.5/2.2/3.2/4%/s ·
gathering: herbs +10/29/53/82/114/150%
| Lv | Ability |
|---|---|
| 1 | **Minor Prayer** (board) — small heal over time |
| 5 | **Minor Blessing** (board) — shield + defense boost on an ally |
| 12 | **Sacred Circle** (board) — zone: allies take less damage, heal slowly |
| 20 | **Sanctuary** — brief no-damage zone |
| 30 | *Sanctuary Ascended* — larger, follows the caster, also cleanses |

## 4. What goes with what

Build spines (the 12 endgame builds) live in
[`REBIRTH_AND_BUILDS.md`](REBIRTH_AND_BUILDS.md) §2. Trait → affinity map:

| Trait | Loves | Why |
|---|---|---|
| Lynx Eye | Sniper, Justicar, Berserker · Precision | crit multiplies burst windows and marked targets |
| Agile Hands | Berserker, Scout · Precision | attack-speed stacking; also faster tool swings |
| Physical Training | all knight + ranger schools · Valor | additive with school passives in the damage category |
| Arcane Practice | mage schools, Holy Avenger · Attunement | same, magic side |
| Perseverance | Berserker (Cry), Trapper (zones), Light Priest (HoTs), Scout (Sprint), Invoker | anything with a duration |
| Inferno | Trapper, Justicar, Arcanist | stuns/slows/nets last longer — with Trapper's control passive (stronger) it's the full CC identity |
| Executioner | Sniper, Justicar · anything running Lynx Eye | crit chance × crit damage multiply |
| Leech | Berserker, Holy Avenger | funds the HP-spending kits (Frenzy, Reprisal) |
| Retribution | Sentinel · Valor | tanks answer melee swarms; pairs with Provoke/aggro |
| Brawler | Berserker, Sentinel, Holy Avenger | melee uptime; Frenzy/Reprisal trade HP |
| Bastion | Sentinel · Valor | the tank stack (multiplies with Sentinel's armor passive) |
| Evasion | Scout, Trapper | kite builds — dodge what reaches you |
| Guardian | Sentinel, Light Priest, Oracle | party-facing mitigation for anchors and healers |
| Life Essence | any frontliner partied with a cleric | receiving-end amplifier; pairs across players, not just within a build |
| Clarity | every caster + healer | rotation fuel |
| Prospector / Woodsman | Valor's gathering identity | class innate × gear amplifier = the server's best gatherers |

Cross-player note: Guardian + Life Essence + the cleric schools form the
party-synergy triangle — the first deliberately multiplayer trait web.

## 5. Holes — all filled (2026-07-10 resolution log)

1. **Trapper passive → Control** (new stat: slows are X% stronger). More
   work than "physical" (one slow-potency hook in EnemyService) but it
   completes the CC identity: Inferno makes control LAST longer, Control
   makes it BITE harder, Master Trapper spreads it wider.
2. **Life Essence → healing received.** Potions, ally spells, on-hit heals;
   passive regen excluded (no Brawler/Devotion double-dip). Cross-player by
   design — the frontliner buys it to make their cleric better.
3. **Stat-space holes → three new traits, two confirmed exclusions.**
   Added: *Executioner* (crit damage, weapon pool), *Leech* (lifesteal on
   weapon hits, weapon pool), *Retribution* (melee reflect, armor pool).
   Excluded FOREVER unless proven wrong: move speed (lives in
   Scout/Precision only — kiting speed on gear breaks melee) and cooldown
   reduction (a balance grenade in every game that ships it; Perseverance
   is the safe cousin). Mana cost reduction folds into Clarity's niche.
4. **Gathering reserves → defs written** (§1 table), gated only on content:
   herb nodes + sickle (Herbalist), potion recipes (Alchemist), the
   DropService quantity hook (Plunderer).
5. **Board leftovers → placed.** The sniper's guaranteed-crit stance merged into
   Overwatch (aim mode: distance damage + guaranteed crit); the knight's
   area-stun ultimate lives inside *Second Wind Ascended* (stagger + taunt
   on trigger).
6. **Apex first-pass numbers** (all vs. player damage output at equal
   points; tune in playtest):

| Apex | First pass |
|---|---|
| Meteor | 400% magic, 12-stud AoE, 1.5s telegraph · 45s cd |
| Singularity | pull 15 studs → center, 250% magic + 1s stun · 40s cd |
| Legion | grants the 3rd familiar; active: familiars +100% damage 10s · 40s cd |
| Bloodbath | 8s window: kills heal 10% max HP and extend Frenzy 1.5s · 50s cd |
| Aegis | party shield 25% of each member's max HP, 6s · 45s cd |
| Tribunal | mark all enemies in 12 studs 6s; marked take +30% damage from EVERYONE · 40s cd |
| One Shot, One Kill | guaranteed crit, +100% crit damage, executes below 15% HP · 45s cd |
| Master Trapper | place 3 pre-armed traps up to 20 studs away · 40s cd |
| Arrow Rain | 350% physical over 4s, 14-stud zone · 45s cd |
| Miracle | instant 40% max-HP heal party-wide + cleanse · 60s cd |
| Crusade | 8s: party gains 15% lifesteal, caster +25% damage · 50s cd |
| Prophecy | 3s: no party member's HP can drop below 1 · 90s cd |

7. **Super crits + the ✦35 band (decided 2026-07-10).** Crit chance
   overflow: each full 100% guarantees the crit; the remainder is the
   chance the crit upgrades a tier (×2 → ×3 → ×4...). 120% total = every
   hit crits, 20% of them hit ×3. Expected damage in the overflow band:
   ×2 + overflow/100 — smooth, convex-friendly scaling past the old cap.
   Interaction rule: a super crit multiplies the FINAL crit multiplier by
   1.5, AFTER Executioner (Executioner ✦25 → crits ×3.2, supers ×4.8) —
   Lynx + Executioner is deliberately the most explosive endgame pairing.
   Implementation: the crit roll in EnemyService's damage path gains the
   overflow tier check; DamageIndicatorUI gets a bigger super-crit pop.
   With this, Lynx Eye graduates to depth 30 (✦30→110%). Attack speed is
   also cleared to extend (needs a tech check on the swing-cooldown floor
   + animation speeds ~150%+, not a design change). Dodge and durations
   stay capped. FUTURE: a ✦35 prestige band (~+26% over ✦30 values) for
   the scaling cores only — PT/AP/AH/Brawler/Bastion/Lynx — ships when
   live data shows R100+ perm surplus piling up with nowhere to go; purely
   additive, no migration.
8. **Full rebalance pass (2026-07-10)** — every board-inherited number
   re-derived from the framework (standard grid, curve formula, depth
   classes, hybrid discounts, level-scaled rarity bonus — see the header
   block). Perseverance/Inferno resolved by re-derivation, not by picking a
   side: both are depth-16 traits, Perseverance tops at +40% (cd-bounded,
   safe), Inferno tops at +50% and SHIPS TOGETHER WITH enemy-side
   diminishing returns (same 100/50/25% shape as the player-side rule) so
   party CC-stacking can't permastun.

Remaining work is tuning, not design: γ playtest (TRAITS_V2 §8.7) and
balancing every number above against live combat.

## 6. Canonical English names & code ids (game language = English)

Class ids are already English (`knight` / `archer` / `mage` / `cleric`) —
only their DISPLAY names need translating (Knight / Archer / Mage / Cleric,
in `Classes.lua` and anywhere UI-facing). The shipped cleric schools and
spells still use Spanish IDS in `Spells.lua`; they rename as follows:

| Old id | New id | Display name |
|---|---|---|
| `sacerdote_luz` | `light_priest` | Light Priest |
| `vengador_sagrado` | `holy_avenger` | Holy Avenger |
| `oraculo` | `oracle` | Oracle |
| `toque_curativo` | `healing_touch` | Healing Touch |
| `bendicion` | `blessing` | Blessing |
| `renacimiento` | `revival` | Revival — NOT "Rebirth": reserved for the rebirth system |
| `golpe_sagrado` | `holy_strike` | Holy Strike |
| `represalia` | `reprisal` | Reprisal |
| `juicio_divino` | `divine_judgment` | Divine Judgment |
| `purificar` | `purify` | Purify |
| `vinculo_espiritual` | `spirit_link` | Spirit Link |
| `intervencion` | `intervention` | Intervention |

**Migration (ids are persisted!):** school ids live in rolled items'
`meta.traits` keys (backend `inventory_items.meta`) and spell ids in
persisted hotbar binds (`spell:<id>` in the profile). The rename ships with
a LEGACY_IDS alias map applied at read time in both places — backend
`sanitizeMeta`/fetch path translates old→new keys, and `HotbarBinds`
translates `spell:<old>` on load (same pattern as its flat-map→pages
migration). No DB rewrite needed; writes always use new ids.
