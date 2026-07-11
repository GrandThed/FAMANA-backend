# FAMANA Art Backlog — Style A (Faceted low-poly)

The game's art direction is **Style A: faceted low-poly** — visible irregular
triangle facets, flat colors (no textures), one mesh per asset. Reference file:
[`roblox/src/assets/StyleIterations/FAMANA_StyleIterations.blend`](../roblox/src/assets/StyleIterations/FAMANA_StyleIterations.blend)
(comparison renders live next to it). Game-ready exports live in
[`roblox/src/assets/StyleA/`](../roblox/src/assets/StyleA/) — one folder per
asset, OBJ + MTL, exported at **×3.5 scale (≈ studs)**, bottom-centered at the
origin, Y-up.

**Creature recipe** (proven on goblin/slime/wolf): overlap anatomy primitives →
voxel remesh into one body → decimate to ~1–2k irregular tris → flat shade;
eyes/teeth/cloth/gear stay separate colored parts, joined at the end.

## Done — exported to `assets/StyleA/`

| Asset | Game mapping | Tris |
|---|---|---|
| Goblin | `goblin` enemy (EnemyService) — club included, CoC-style approved look | ~3.9k |
| Slime | `slime` enemy | ~550 |
| TreeOak | `tree` node (GatheringService, yields wood) | ~300 |
| RockStone | `rock` node (yields stone) — plain variant | ~160 |
| RockCopper | `rock` node with copper-bonus flavor (proud orange crystals) | ~240 |
| RockIron | `iron_rock` node (yields iron_ore) | ~280 |
| RockCluster | decorative multi-rock cluster (copper + iron mixed) | ~580 |
| RockGold | future gold-ore node / rare vein | ~260 |
| TreePine | decor / future tree variant | ~140 |
| Stump | decor (felled-tree marker) | ~100 |
| Sword | `sword_basic` visual reference | ~80 |
| Staff | `staff_basic` (emissive orb crystal) | ~120 |
| Bow | `bow_basic` | ~120 |
| Axe | `axe_basic` | ~100 |
| Pickaxe | `pickaxe_basic` | ~90 |
| Forge | `simple_forge` station (emissive ember mouth) | ~160 |
| Chest | loot container / decor (not yet a game item) | ~150 |
| LogBench | decor seat | ~140 |
| Campfire | decor / candidate cooking station (emissive flames) | ~290 |

Also in the .blend but not exported: **Wolf** (~1.8k tris, `StyleA_Expanded`) —
ready if a wolf enemy gets added; v1/v2 goblins kept for reference only.

## To create — content that has NO model anywhere

From `backend/content/items.json` vs `shared/ItemModels.lua`:

- [ ] `axe_copper` — copper-headed axe (recolor/variant of Axe)
- [ ] `pickaxe_copper` — copper-headed pickaxe (variant of Pickaxe)
- [ ] `emblem_light_priest` (ring)
- [ ] `emblem_holy_avenger` (ring)
- [ ] `emblem_oracle` (ring)
- [ ] `hardwood` — resource chunk (darker wood log)
- [ ] `copper_ore` — ore chunk (rock + copper flecks)
- [ ] `copper_ingot` — ingot bar
- [ ] `iron_ore` — ore chunk
- [ ] `iron_ingot` — ingot bar

World content without a model:

- [ ] `hardwood_tree` node — needs a visually distinct tree (darker/denser than TreeOak)
- [ ] `crafting_table` station — has an ArtKit spec only; wants a Style-A mesh
- [ ] **Marla the Trader** (`general_goods` vendor) — humanoid NPC, biggest missing piece

## To upgrade — ArtKit specs that eventually want Style-A meshes

Existing `ItemModels.lua` block-built specs, in priority order:

- [ ] Weapons: `sword_iron`, `sword_duelist` (distinct silhouettes/tiers vs Sword)
- [ ] Armor (paper doll + item stands): leather set (`helmet_leather`,
  `chest_leather`, `gloves_leather`, `legs_leather`, `boots_leather`),
  `helmet_bastion`, `chest_colossus`, `boots_evader`
- [ ] Rings/emblems: `ring_vitality`, `ring_focus`, `ring_brawler`, `ring_lynx`,
  `emblem_pyromancer`, `emblem_berserker`
- [ ] Resources/misc: `wood`, `stone`, `slime_goo`, `goblin_ear`, `torch`, `arrow`

## Nice-to-have world props (no game system yet, pure ambience)

Crates & barrels · fences · a well · vendor market stall (for Marla) · signposts
· banners · bushes/grass clumps · mushrooms · ruins/wall pieces · small bridge ·
border/teleport markers for cell edges.

## Roblox uploads (Open Cloud)

All 19 assets are uploaded to Roblox as Model assets (FBX) under the key
owner's account. Asset ids live in
[`roblox/src/assets/StyleA/ROBLOX_ASSET_IDS.md`](../roblox/src/assets/StyleA/ROBLOX_ASSET_IDS.md)
(+ `roblox_asset_ids.json` for scripts). Re-upload / upload new assets with
`node scripts/upload_styleA_assets.mjs [NameFilter]` — it reads
`ROBLOX_API_KEY` from `.env`, skips names already in the manifest. Insert in
Studio via Toolbox → Inventory → My Models, or `InsertService:LoadAsset(id)`.

**The game loads these at boot.** `shared/MeshAssets.lua` maps game ids →
asset ids; `server/MeshAssetService.lua` inserts them on server start (item
models into `ReplicatedStorage.Assets` — the override folder ToolService/
ItemModels honor — world models into `ReplicatedStorage.MeshModels`, cloned
by EnemyService/GatheringService/CraftingService). Every consumer falls back
to its ArtKit look when a load fails, so Studio-without-asset-access keeps
working. To swap a model: re-upload, put the new id in `MeshAssets.lua`.

## Importing into Studio (manual OBJ route)

1. Studio → **Asset Importer** (Home → Import 3D) → pick the `.obj`.
2. Import as a single Model; Studio splits it into one MeshPart per material —
   keep them grouped, set a **PrimaryPart** (gameplay anchor; gathering nodes
   carry the `Depleted` attribute on it, see CLAUDE.md).
3. Scale is already ≈ studs (goblin ≈ 4.7). No rescale needed.
4. Emissive parts (staff orb, forge mouth, campfire flames) import as plain
   colors — set those MeshParts' `Material = Neon` in Studio to restore the glow.
