-- Uploaded Style-A mesh assets (the faceted low-poly art direction — see
-- docs/ART_BACKLOG.md). Ids mirror roblox/src/assets/StyleA/roblox_asset_ids.json,
-- uploaded via scripts/upload_styleA_assets.mjs. MeshAssetService loads these
-- at boot; every consumer falls back to its ArtKit look when a load fails.
--
-- The FBX exports are pre-baked for Roblox (studs scale, +Y up, -Z front,
-- bottom-centered) and split into ONE OBJECT PER MATERIAL, named after it
-- (fam_*): the pipeline drops material colors, so MeshAssetService recolors
-- each part by name from the palette below.

local MeshAssets = {}

-- Items land in ReplicatedStorage.Assets[<itemId>] — the custom-model
-- override folder ToolService/ItemModels already honor. `grip` is the height
-- (studs above the model's base) where the hand holds it; MeshAssetService
-- adds an invisible Handle part there.
MeshAssets.items = {
	sword_basic = { assetId = 127767149272624, grip = 0.7 },
	staff_basic = { assetId = 87600364107340, grip = 2.4 },
	bow_basic = { assetId = 131363212695848, grip = 2.6 },
	axe_basic = { assetId = 102257619570241, grip = 1.1 },
	pickaxe_basic = { assetId = 71680183113559, grip = 1.1 },
}

-- World models land in ReplicatedStorage.MeshModels[<key>]; the enemy,
-- gathering and crafting services clone them when present. The `rock` node
-- uses the copper-flecked mesh: mining it yields stone plus a copper bonus,
-- and the crystals telegraph that. (The slime keeps its classic translucent
-- ArtKit look by choice — its mesh stays uploaded but unwired.)
MeshAssets.world = {
	goblin = { assetId = 98715900781376 },
	tree = { assetId = 96257985799628 },
	rock = { assetId = 122513009887645 },
	iron_rock = { assetId = 88791112606468 },
	simple_forge = { assetId = 138958981450463 },
}

-- Flat colors by Blender material name (what each exported part is called).
-- Longest name wins on substring matches (fam_wood_dark before fam_wood).
-- The *_emit parts also turn Neon in MeshAssetService.
MeshAssets.palette = {
	fam_skin = Color3.new(0.36, 0.55, 0.22),
	fam_skin_dark = Color3.new(0.24, 0.38, 0.15),
	fam_gskin = Color3.new(0.45, 0.71, 0.29),
	fam_gskin_dark = Color3.new(0.30, 0.52, 0.20),
	fam_ear_tip = Color3.new(0.77, 0.68, 0.42),
	fam_eye = Color3.new(0.95, 0.75, 0.15),
	fam_tooth = Color3.new(0.92, 0.88, 0.78),
	fam_black = Color3.new(0.06, 0.06, 0.06),
	fam_pants = Color3.new(0.36, 0.26, 0.16),
	fam_cloth = Color3.new(0.42, 0.26, 0.14),
	fam_cloth_red = Color3.new(0.55, 0.18, 0.14),
	fam_leather = Color3.new(0.45, 0.32, 0.18),
	fam_rock = Color3.new(0.42, 0.43, 0.46),
	fam_rock_dark = Color3.new(0.30, 0.31, 0.34),
	fam_copper = Color3.new(0.80, 0.42, 0.18),
	fam_iron = Color3.new(0.62, 0.66, 0.72),
	fam_steel = Color3.new(0.72, 0.75, 0.80),
	fam_gold = Color3.new(0.82, 0.60, 0.22),
	fam_wood = Color3.new(0.38, 0.25, 0.14),
	fam_wood_dark = Color3.new(0.27, 0.17, 0.10),
	fam_leaf = Color3.new(0.27, 0.48, 0.20),
	fam_leaf_light = Color3.new(0.40, 0.62, 0.26),
	fam_pine = Color3.new(0.18, 0.40, 0.24),
	fam_string = Color3.new(0.88, 0.86, 0.80),
	fam_orb = Color3.new(0.30, 0.55, 0.95),
	fam_ember = Color3.new(0.93, 0.42, 0.12),
	fam_flame = Color3.new(0.98, 0.75, 0.22),
	fam_slime = Color3.new(0.36, 0.66, 0.30),
	fam_slime_dark = Color3.new(0.22, 0.44, 0.20),
	fam_fur = Color3.new(0.45, 0.42, 0.40),
	fam_fur_dark = Color3.new(0.30, 0.28, 0.27),
}

return MeshAssets
