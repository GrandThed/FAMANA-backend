# Rebirth & Endgame Builds — the long game

> Deep dive on top of [`TRAITS_V2.md`](TRAITS_V2.md) (convex curve + catalog).
> Innate class traits are **CONFIRMED** (2026-07-10); this doc designs what
> sits above the level-20 cap: three endgame builds per class, and a rebirth
> system that lets a max-rebirth (R200) character run TWO of those builds at
> once with an innate at 30 — deliberately, absurdly powerful.
>
> Status: PROPOSAL with worked math. Every constant is a named knob (§7).

Grounding numbers used throughout (from code):

- Class level hard cap **20** (`Config.PlayerLeveling.maxLevel`); XP to next =
  `50 + (level−1)·25` → **5,225 XP for a full 1→20 run**.
- Base crit 15%, crits deal 2× (`Config.Combat`).
- 10 paper-doll slots; item points = item level + rarity bonus, with rarity
  also shaping concentration (TRAITS_V2 §6) → **~200–220 raw gear points at
  L20**.
- Innate trait points = active class level (TRAITS_V2 §5), so innate caps at
  20 without rebirths — "level 30 innate" = 10 above the theoretical max.

## 1. What an endgame build IS (cost model)

**A build IS a subclass** (clarified 2026-07-10): the twelve schools are the
twelve endgame builds — three per class, each with one main direction — and
the trait spine exists to serve its school. Mechanically a finished build is
that school's full kit plus the concentrated points around it:

```
school @ 20        (full base kit + hybrid passive; apex waits at 30)
primary trait @ ✦25 (prestige)
secondary trait @ 16–20
tertiary trait @ 8–12
────────────────────────────
≈ 70–75 TARGETED points  (+ the class innate, which is free — it's level-fed)
```

The school's base kit completes at 20, but every school now carries **4
abilities** — the 4th is an apex spell at 30 (TRAITS_V2 §4) — so those
extra ~10 points are the above-and-beyond target that soaks endgame surplus
and rebirth perm points.

Supply check at rebirth 0: ~200 raw gear points, of which realistically
**~120–140 land on-spine** — concentration comes from rarity now (TRAITS_V2
§6: legendaries/epics carry your trait deep, commons only splash), so
"on-spine" means hunting high-rarity pieces in your primary traits, with
vendors/trading closing the rest. That funds **exactly one full build plus
pocket change** — which is the intended baseline: a fresh level-20 is a
one-build character. Rebirth is what pays for the second.

## 2. The twelve builds — one per subclass, one main direction each

Spines use the v2 catalog (retuned ladders). ✦ = prestige tier. The spine is
the *recommended* endgame expression of each school — players can deviate,
but content, drops and the tracker's "recommended" hints steer here.

| Class | Subclass (= the build) | Main direction | Trait spine (primary ✦ / secondary / tertiary) |
|---|---|---|---|
| Knight | **Berserker** | melee bruiser DPS — Frenzy windows | Physical Training ✦25 / Agile Hands 16 / Brawler 8 |
| Knight | **Sentinel** | party tank — Bulwark anchor | Bastion ✦25 / Brawler 20 / Guardian 8 |
| Knight | **Justicar** | stun-burst executioner — Verdict | Lynx Eye ✦25 / Physical Training 16 / Inferno 8 |
| Archer | **Sniper** | single-target deletion | Lynx Eye ✦25 / Executioner 16 / Physical Training 8 |
| Archer | **Trapper** | zone control / CC denial | Inferno 16 / Evasion 16 / Physical Training 12 |
| Archer | **Scout** | mobile skirmisher | Agile Hands ✦25 / Evasion 16 / Physical Training 8 |
| Mage | **Pyromancer** | AoE burst — Supernova | Arcane Practice ✦25 / Clarity 16 / Perseverance 8 |
| Mage | **Arcanist** | sustained control DPS | Arcane Practice 20 / Inferno 16 / Clarity 12 |
| Mage | **Invoker** | familiar army / attrition | Arcane Practice 20 / Perseverance 16 / Brawler 12 |
| Cleric | **Light Priest** | pure healer — Revival | Clarity 16 / Perseverance 12 / Guardian 12 |
| Cleric | **Holy Avenger** | battle-cleric — heals by hitting | Arcane Practice ✦25 / Brawler 16 / Leech 8 |
| Cleric | **Oracle** | anti-death support — Intervention | Guardian 20 / Life Essence 16 / Clarity 12 |

(Rebalanced 2026-07-10 to the standard grid; Sniper now runs Executioner and
Holy Avenger runs Leech — the two new traits slot straight into spines.)

Design checks: every class covers a damage, a tank/control, and a
support/utility direction; primaries stay distinct within a class except
the mage damage schools, which both live on Arcane Practice and split on
Inferno vs Perseverance vs Clarity; all twelve spines cost ~70–75 points so
no class is cheaper to "finish".

## 3. The rebirth loop

**Requirement:** reaching level 20 in ANY class — no other prerequisite.
**On rebirth (decided 2026-07-10 — supersedes the single-class reset):**
**ALL classes reset to level 1 / 0 XP.** Equipped gear goes inert
automatically (existing gate — no new rule needed) and wakes up as you
re-level. Consequence to know: leveling a second class to 20 before
rebirthing earns nothing extra — the optimal loop is one class per cycle,
and switching class between cycles is free strategy, not lost progress.
**The grant:** **+1 permanent point into a SHARED pool**, and at every
rebirth you may **fully reallocate** every accumulated point across any
traits and schools (the altar is a free respec). Permanent points feed the
same ladders as gear points (additive), capped per trait at its ladder's top
tier, and they are class-agnostic — they're on no matter what you play.
**Counter:** one character total. **Caps at 200.**

Permanent points are the whole engine: they are *perfectly targeted* (no roll
luck), *reallocatable* (no build regret — swap your whole spine when you swap
subclass), and they survive the reset — every rebirth makes the next
re-level faster and the endgame doll richer. 100 rebirths ≈ one full build
spine permanently online, which frees the ENTIRE gear doll for a second
spine.

### Milestones (all keyed to the one total)

| Total | Reward |
|---|---|
| every 5 | +1 innate cap above 20 → **innate 30 at R50** (the cap is universal — whichever innate is active enjoys it) |
| 100 | **Twin Soul** — a second innate of your choice stays active at a flat level 20 (choice can change at any rebirth; flat because all class levels reset each cycle) |
| 200 | **Apotheosis** — BOTH active innates jump to their level-30 tier + ascended capstones |

Plus a smooth global: **Legacy — +0.4% damage dealt and +0.4% max HP per
rebirth** (its own multiplicative category) → ×1.8 damage and ×1.8 HP at
R200. Legacy is class-agnostic (it rides the character, not the class).

## 4. The math — how absurd is R200?

Model (matches the stacking rule: additive within category, categories
multiply; armor EHP = (100+armor)/100):

```
DPS index = (1 + school% + trait dmg% + innate dmg%)   ← additive category
          × (1 + attack speed%)
          × (1 + critChance · (critMult − 1))          (crit chance capped 100%)
          × Legacy
EHP index = (1 + hp%) × (100 + armor)/100 × Legacy
```

Worked example — Warbringer knight, naked L20 = 1.0 / 1.0:

| Stage | Allocation highlights (rebalanced grid) | DPS | EHP | vs fresh endgame |
|---|---|---|---|---|
| **R0** fresh L20, good gear | Berserker 20 (+44%), PT 20 (+73%), AH 12 (+30%), Brawler 8 (+18% hp), Bastion 5 (12 armor), innate Valor 20 (+15%/+20 armor), base crit 15% | **≈ 3.5** | **≈ 1.6** | 1× |
| **R50** (innate 30) | perm 50: PT 30 (+135%), Lynx 20 (+61% crit); gear: school + AH 16 (+47%) + Brawler 12 + Bastion 8; Valor 30 (+27%/+36); Legacy ×1.2 | **≈ 10** | **≈ 2.6** | ~2.8× / ~1.6× |
| **R100** Twin Soul | perm 100: PT 30 (+135%), Lynx ✦25 (+85% crit → capped at 100% with base), AH ✦25 (+91%), Berserker 20; gear freed → Brawler 20 (+71% hp), Bastion 20 (98 armor), Guardian 8; Twin Soul innate Precision @20 (+13% AS); Legacy ×1.4 | **≈ 18** | **≈ 5.5** | ~5× / ~3.4× |
| **R200** Apotheosis | perm 200 = spine A complete (school 20 + PT 30 + Lynx ✦25 + AH ✦25) + spine B core (Brawler ✦25, Bastion ✦25, Guardian 20, Sentinel 20); gear = pure surplus (Evasion, Life Essence, Clarity, 2nd school topped); both innates 30; crit capped 100%; Legacy ×1.8 | **≈ 25** | **≈ 12** | **~7× / ~7.5×** |

So the max-rebirth character is ~7× the damage and ~7.5× the durability of a
fresh endgame player, runs **two complete subclass kits simultaneously**
(e.g. Sentinel's tank spine under Berserker's bruiser spine — two school
capstones, two ascended innate actives),
and one-shots regular L20 content. That is the intended "absurdly powerful" —
strong enough to feel mythic, finite enough to balance content around
(rebirth-tier zones just extend `mobLevel` ranges past 20).

Content note: mobs scale +15% hp / +10% dmg per level linearly — a "rebirth
cell" with L40–60 mobs (~7–10× base hp) is exactly the arena an R100–R200
character needs, and gives item levels above 20 somewhere to drop later if we
ever raise gear past the class cap.

## 5. Pacing — every rebirth gets FASTER (MU-style, decided 2026-07-10)

**No XP tax.** The requirement is a flat 5,225 XP (1→20) every run, forever —
like MU Online's resets, where the power you keep (there: stat points; here:
the shared perm-point pool, innate overlevels, Legacy — all gear-independent,
so they work from minute one of a fresh run) makes each consecutive re-level
faster. Acceleration IS the fantasy; the 200 cap is what bounds the system.

Estimated loop times, scaling XP/hour with the §4 power indices (early runs
are slower than the index suggests because gear sits inert until re-leveled;
perm points don't care):

| Stage | est. per rebirth | cumulative |
|---|---|---|
| R1–10 | ~2.5 h | ~25 h |
| R11–25 | ~2 h | ~55 h |
| R26–50 | ~1.5 h | ~90 h |
| R51–100 | ~50 min | ~130 h |
| R101–150 | ~30 min | ~155 h |
| R151–200 | ~20 min | **~175 h** |

So R200 lands around **150–200 hours of focused farming** (less in party XP
range) — a hardcore-season goal, not a years-long one. If that reads too
fast, the levers that DON'T break the every-rebirth-faster feel:

- **Gold/material cost per rebirth** that scales with the count (economy
  sink — the altar wants tribute).
- **Content gating** — past ~R50, regular L20 cells stop being efficient XP
  and rebirth-tier zones (mobs L40+) become the real farm; pacing then lives
  in zone difficulty, not in the XP formula.
- Raising the base XP curve for everyone (blunt, touches non-rebirth play).

Explicitly rejected: per-rebirth XP inflation (a tax makes later loops
slower, the opposite of the MU feel).

## 6. Implementation map

Persistence (backend):

- `players` gains `rebirth JSONB NOT NULL DEFAULT '{}'` —
  `{ total, perm: { physical_training: 30, … }, twinSoul: "archer" }`,
  sanitized like `meta` (trait/school ids ≤32 chars, per-trait points ≤
  ladder cap, Σ perm = total ≤ 200). Auto-migrated via the existing
  `ALTER TABLE IF NOT EXISTS` pattern in `schema.sql`.
- New route `POST /player/:id/rebirth { allocations, twinSoul? }` —
  transactional: validate active class at 20 + total < 200 + the FULL
  allocation map (it replaces the old one — the free-respec rule — so
  validate Σ = new total and every per-trait cap), reset EVERY class's
  level/xp in the profile, bump total, enqueue a `player_events` row (new
  kind `rebirth`) so a second server/admin view refreshes. Admin dashboard:
  show counters + audited edit.

Roblox server:

- **RebirthService** — altar NPC with ProximityPrompt (VendorService
  pattern), `RequestRebirth` remote → backend call → on success: apply the
  class reset live (PlayerService level/xp attrs + respec, same shape as
  AdminSyncService's `stats` path), celebration (LevelUpUI-style, bigger).
- **SynergyService** — `totalsFor` merges gear points + the shared perm pool
  (class-agnostic) + the active class's innate points (= class level, cap
  20 + floor(total/5) up to 30) + the Twin Soul innate at flat 20 (30 after
  Apotheosis) once R100. Legacy is a separate registered mult (damage hook +
  HealthService max-HP hook).
- Innate ladders get their 25/30 tiers + ascended capstones in the class
  trait defs (TRAITS_V2 §5 table).

Roblox client:

- **RebirthUI** — confirm flow ("this resets ALL your classes to level 1") +
  the full allocation respec screen (catalog list, drag points freely, must
  spend exactly `total`; Twin Soul class picker once unlocked).
- **SpellTrackerUI / CharacterUI** — perm points render inside the same
  totals with a distinct marker (gold ◆); CharacterUI adds rebirth count +
  Legacy line; innate rows show 20+n cap progress.

## 7. Knobs & open decisions

1. **Grant size** — 1 perm point/rebirth (proposed). 2 would halve the road
   to dual-build (~R50) and make R200's 400 points overflow the catalog.
2. **Perm points into schools** — proposed YES (needed to permanently own a
   spell kit); alternative: traits only, schools stay gear-only.
3. **Legacy rate** — 0.4%/rebirth (×1.8 at R200). The "absurdity dial":
   0.25% → ×1.5, 0.5% → ×2.
4. **Twin Soul at R100** — flat 20 until Apotheosis lifts it to 30
   (proposed; it can't ride a class level anymore since every rebirth resets
   all of them).
5. ~~**XP tax slope**~~ — DECIDED 2026-07-10: none. Every rebirth gets
   faster, MU-style (§5); the cap and content do the bounding.
6. **Rebirth requirement** — level 20 exactly, or also a gold/quest cost as a
   sink? (With no XP tax this is now the main pacing lever, see §5.)
7. ~~**Per-class or shared perm pools**~~ — DECIDED 2026-07-10: one shared
   pool, fully reallocatable at every rebirth. Sub-question: is the respec
   free forever (proposed), or does re-allocating cost gold past some count
   (sink + commitment pressure)?
8. **Cap 200 semantics** — hard stop (proposed) vs soft cap (Legacy stops,
   perm points continue).
