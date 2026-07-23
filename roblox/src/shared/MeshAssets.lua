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
	-- resources & misc (thumbnails + drops)
	wood = { assetId = 85179031784666 },
	hardwood = { assetId = 79214490161481 },
	stone = { assetId = 137079906928154 },
	slime_goo = { assetId = 105386601119574 },
	goblin_ear = { assetId = 78607455271862 },
	torch = { assetId = 129057767919098, grip = 1.0 },
	arrow = { assetId = 90864237135061 },
	copper_ore = { assetId = 76596920715009 },
	iron_ore = { assetId = 75509830043365 },
	copper_ingot = { assetId = 84333363630588 },
	iron_ingot = { assetId = 116281909258676 },
	-- camp furniture ITEMS (thumbnails/drops share the world models below)
	cofre_campamento = { assetId = 115944771848024 },
	carpa_campamento = { assetId = 121085103547372 },
	olla_campamento = { assetId = 109233509139950 },
	alfombra_campamento = { assetId = 78239886476338 },
	farol_campamento = { assetId = 117384952474171 },
	trofeo_campamento = { assetId = 136523617486297 },
	crafting_table = { assetId = 75265545325459 },
	simple_forge = { assetId = 102893265088538 },
}

-- World models land in ReplicatedStorage.MeshModels[<key>]; the enemy,
-- gathering and crafting services clone them when present. The rock pools
-- split by yield: `stone_rock` gives stone only, `copper_rock` copper ore
-- (the nuggets telegraph it), `iron_rock` iron ore. (The slime keeps its
-- classic translucent ArtKit look by choice — its mesh stays uploaded but
-- unwired.)
MeshAssets.world = {
	goblin = { assetId = 98715900781376 },
	-- Gathering trees are VARIANT POOLS (new_art_style/variants — 5 authored
	-- structural variants per species: branch layout, height, tier/limb
	-- counts, palette bias); every placed node draws a random one so forests
	-- read less regular.
	-- `scale` multiplies the mesh at placement (MeshAssetService.place).
	tree = { scale = 2.25, assetIds = { 72344195310639, 107593124794028, 117032412913468, 79125791269192, 105236673635744 } }, -- green oak 01-05
	hardwood_tree = { scale = 2.25, assetIds = { 138632698344179, 127398703088981, 74528344057829, 71595350168403, 104059734104173 } }, -- autumn oak 01-05
	-- Wood-variety nodes: both drop plain wood, different biome flavor.
	conifer_tree = { scale = 1.5, assetIds = { 104417345453937, 80497554894490, 112725607111965, 70891102488617, 128070011856338 } },
	dead_tree = { scale = 1.5, assetIds = { 97161715709820, 82951960226063, 76183893695357, 119450274004031, 94378359347271 } },
	-- Rock nodes are variant pools too (new_art_style/rocks — 3 structural
	-- variants each: squat dome / tilted monolith / leaning twin slabs, ore
	-- nuggets scattered over the host rock's side faces).
	stone_rock = { assetIds = { 137910844444218, 79520870706483, 134539682454068 } }, -- plain grey 01-03
	copper_rock = { assetIds = { 104564765245563, 100824972868800, 78565553450595 } }, -- copper-flecked 01-03
	iron_rock = { assetIds = { 102142981623224, 110129547971909, 123429027243726 } }, -- iron 01-03
	simple_forge = { assetId = 138958981450463 },
	-- camp furniture + the tier-scaled campfire dressing
	chest = { assetId = 115944771848024 },
	tent = { assetId = 121085103547372 },
	crafting_table = { assetId = 75265545325459 },
	cauldron = { assetId = 109233509139950 },
	rug = { assetId = 78239886476338 },
	lantern = { assetId = 117384952474171 },
	trophy = { assetId = 136523617486297 },
	campfire = { assetId = 135244778048023 },
}

-- Animated skinned-mesh enemies (new_art_style/roblox — one rigged MeshPart
-- with Bones + three published animation clips each). Uploaded via Open Cloud
-- (scripts/upload-enemy-assets.mjs; ids mirror
-- new_art_style/roblox/opencloud/roblox_asset_ids.json). Unlike the static
-- world models these keep their instance hierarchy (bones + the
-- AnimationController the pipeline ships inside the model), so
-- MeshAssetService loads them un-flattened and EnemyService drives the
-- idle/walk/attack tracks. `height` is the authored stud height — enemy defs
-- should keep size.Y close to it so the visual barely rescales (the baked
-- animation offsets assume the authored size). Fronts are -Z (the enemy
-- convention), no flip needed.
MeshAssets.animated = {
	goblin = {
		assetId = 97686843371381,
		height = 3.98,
		animations = { idle = 121725071555551, walk = 115918753604656, attack = 140720132537222 },
	},
	golem = {
		assetId = 138468365554927,
		height = 6.3,
		animations = { idle = 105605400201380, walk = 139612490294747, attack = 81523487745811 },
	},
	spider = {
		assetId = 109971290803819,
		height = 5.36,
		animations = { idle = 118884750774521, walk = 86598766801986, attack = 123852831646787 },
	},
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
	-- new_art_style tree pack materials (M_Tree_* in the source GLBs)
	m_tree_bark = Color3.new(0.252, 0.181, 0.139),
	m_tree_deadbark = Color3.new(0.325, 0.332, 0.351),
	m_tree_leaf_dark = Color3.new(0.234, 0.344, 0.181),
	m_tree_leaf_mid = Color3.new(0.336, 0.475, 0.195),
	m_tree_leaf_light = Color3.new(0.452, 0.622, 0.245),
	m_tree_leaf_pale = Color3.new(0.556, 0.700, 0.296),
	m_tree_leaf_rust = Color3.new(0.653, 0.299, 0.174),
	m_tree_leaf_orange = Color3.new(0.779, 0.452, 0.181),
	m_tree_leaf_amber = Color3.new(0.847, 0.595, 0.198),
	m_tree_leaf_gold = Color3.new(0.827, 0.684, 0.259),
	m_tree_palewood = Color3.new(0.684, 0.645, 0.564),
	m_tree_pine_dark = Color3.new(0.241, 0.400, 0.329),
	m_tree_pine_mid = Color3.new(0.310, 0.494, 0.400),
	m_tree_snow = Color3.new(0.927, 0.947, 0.964),
}

return MeshAssets
