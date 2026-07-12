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
	-- held weapons/tools (grip required: they become Tools). `yaw` spins the
	-- canonicalized template (degrees): the axes/picks arrive edge-to-+Z, and
	-- a held Tool's forward (out of the fist, the swing direction) is -Z —
	-- yaw 180 puts the cutting edge at the front.
	sword_basic = { assetId = 127767149272624, grip = 0.7 },
	sword_iron = { assetId = 97025410736955, grip = 0.7 },
	sword_duelist = { assetId = 113061284197497, grip = 0.6 },
	staff_basic = { assetId = 87600364107340, grip = 2.4 },
	bow_basic = { assetId = 131363212695848, grip = 2.6 },
	axe_basic = { assetId = 102257619570241, grip = 1.1, yaw = 180 },
	axe_copper = { assetId = 126935822934292, grip = 1.1, yaw = 180 },
	pickaxe_basic = { assetId = 71680183113559, grip = 1.1, yaw = 180 },
	pickaxe_copper = { assetId = 89911475912573, grip = 1.1, yaw = 180 },
	-- paper-doll gear (thumbnails, drops, item stands — never held)
	helmet_leather = { assetId = 75707656342609 },
	chest_leather = { assetId = 128783349712113 },
	gloves_leather = { assetId = 119445448188951 },
	legs_leather = { assetId = 137102745295444 },
	boots_leather = { assetId = 122404557128536 },
	helmet_bastion = { assetId = 120862809448577 },
	chest_colossus = { assetId = 91602323140865 },
	boots_evader = { assetId = 86564891630994 },
	ring_vitality = { assetId = 73211628022695 },
	ring_focus = { assetId = 101126665122368 },
	ring_brawler = { assetId = 116557944733582 },
	ring_lynx = { assetId = 94962801011904 },
	emblem_pyromancer = { assetId = 100778249359982 },
	emblem_berserker = { assetId = 129450135148808 },
	emblem_light_priest = { assetId = 75104327537098 },
	emblem_holy_avenger = { assetId = 76973174528352 },
	emblem_oracle = { assetId = 115367282456462 },
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
	fam_leather_dark = Color3.new(0.32, 0.22, 0.12),
	fam_steel_dark = Color3.new(0.52, 0.55, 0.60),
	fam_leaf_dark = Color3.new(0.20, 0.36, 0.15),
	fam_ruby = Color3.new(0.85, 0.20, 0.20),
	fam_sapphire = Color3.new(0.25, 0.45, 0.90),
	fam_teal = Color3.new(0.20, 0.75, 0.65),
	fam_ivory = Color3.new(0.93, 0.90, 0.80),
}

return MeshAssets
