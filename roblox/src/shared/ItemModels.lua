-- Low-poly models for every item, in ArtKit spec format. One catalog serves
-- both sides: the server builds held Tools from it (ToolService) and the
-- client renders inventory/hotbar thumbnails from it (ViewportFrames).
--
-- Conventions:
--   * The FIRST spec is the grip/primary part and must sit at the origin
--     (no offset) — for equippables it becomes the Tool's Handle and the
--     hand holds its center.
--   * Equippables stand along +Y (up when held); remaining offsets are
--     relative to the first part.
--   * Colors come from ArtKit.Palette — no inline RGB here.

local ArtKit = require(script.Parent.ArtKit)

local V = Vector3.new

local ItemModels = {}

ItemModels.defs = {
	-- ---- weapons ----------------------------------------------------------

	sword_basic = {
		{ name = "Grip", size = V(0.32, 1.1, 0.32), color = "trunkDark" },
		{ name = "Wrap1", size = V(0.38, 0.16, 0.38), offset = V(0, -0.25, 0), color = "trunk" },
		{ name = "Wrap2", size = V(0.38, 0.16, 0.38), offset = V(0, 0.2, 0), color = "trunk" },
		{ name = "Pommel", size = V(0.44, 0.34, 0.44), offset = V(0, -0.72, 0), rot = V(0, 45, 0), color = "steelDark" },
		{ name = "Guard", size = V(1.5, 0.22, 0.5), offset = V(0, 0.66, 0), color = "steelDark" },
		{ name = "Blade", size = V(0.55, 2.5, 0.16), offset = V(0, 2.0, 0), color = "steel" },
		{ name = "Fuller", size = V(0.16, 2.3, 0.2), offset = V(0, 1.95, 0), color = "steelDark" },
		{ name = "Tip", size = V(0.34, 0.6, 0.14), offset = V(0, 3.55, 0), color = "steel" },
	},

	sword_iron = {
		{ name = "Grip", size = V(0.34, 1.2, 0.34), color = "trunkDark" },
		{ name = "Wrap1", size = V(0.4, 0.16, 0.4), offset = V(0, -0.28, 0), color = "trunk" },
		{ name = "Wrap2", size = V(0.4, 0.16, 0.4), offset = V(0, 0.22, 0), color = "trunk" },
		{ name = "Pommel", size = V(0.5, 0.4, 0.5), offset = V(0, -0.78, 0), rot = V(0, 45, 0), color = "gold" },
		{ name = "Guard", size = V(1.7, 0.26, 0.55), offset = V(0, 0.72, 0), color = "gold" },
		{ name = "GuardL", size = V(0.3, 0.4, 0.6), offset = V(-0.85, 0.72, 0), color = "gold" },
		{ name = "GuardR", size = V(0.3, 0.4, 0.6), offset = V(0.85, 0.72, 0), color = "gold" },
		{ name = "Blade", size = V(0.65, 2.9, 0.2), offset = V(0, 2.25, 0), color = "steel" },
		{ name = "Fuller", size = V(0.18, 2.7, 0.24), offset = V(0, 2.2, 0), color = "steelDark" },
		{ name = "Tip", size = V(0.4, 0.7, 0.18), offset = V(0, 4.05, 0), color = "steel" },
	},

	staff_basic = {
		{ name = "Shaft", size = V(0.28, 4.6, 0.28), color = "trunkDark" },
		{ name = "GripWrap", size = V(0.36, 0.8, 0.36), offset = V(0, -0.7, 0), color = "trunk" },
		{ name = "Butt", size = V(0.38, 0.28, 0.38), offset = V(0, -2.35, 0), color = "gold" },
		{ name = "Collar", size = V(0.42, 0.3, 0.42), offset = V(0, 1.75, 0), rot = V(0, 45, 0), color = "gold" },
		{ name = "ProngL", size = V(0.2, 0.9, 0.2), offset = V(-0.32, 2.25, 0), rot = V(0, 0, 15), color = "trunkDark" },
		{ name = "ProngR", size = V(0.2, 0.9, 0.2), offset = V(0.32, 2.25, 0), rot = V(0, 0, -15), color = "trunkDark" },
		{ name = "Orb", shape = "Ball", size = V(0.85, 0.85, 0.85), offset = V(0, 2.8, 0), color = "magic", material = Enum.Material.Neon },
	},

	bow_basic = {
		{ name = "Grip", size = V(0.3, 1.0, 0.34), color = "trunkDark" },
		{ name = "LimbLower", size = V(0.22, 1.7, 0.22), offset = V(0, -1.35, 0), rot = V(0, 0, 12), color = "trunk" },
		{ name = "LimbUpper", size = V(0.22, 1.7, 0.22), offset = V(0, 1.35, 0), rot = V(0, 0, -12), color = "trunk" },
		{ name = "TipLower", size = V(0.16, 0.3, 0.16), offset = V(-0.36, -2.15, 0), color = "steelDark" },
		{ name = "TipUpper", size = V(0.16, 0.3, 0.16), offset = V(-0.36, 2.15, 0), color = "steelDark" },
		{ name = "String", size = V(0.05, 4.3, 0.05), offset = V(-0.36, 0, 0), color = "steel" },
	},

	-- ---- tools -------------------------------------------------------------

	axe_basic = {
		{ name = "Shaft", size = V(0.36, 3, 0.36), color = "trunk" },
		{ name = "Butt", size = V(0.44, 0.3, 0.44), offset = V(0, -1.6, 0), color = "trunkDark" },
		{ name = "Binding", size = V(0.5, 0.55, 0.5), offset = V(0, 1.2, 0), color = "trunkDark" },
		{ name = "HeadCore", size = V(0.9, 0.7, 0.3), offset = V(0.45, 1.35, 0), color = "steelDark" },
		{ name = "Blade", size = V(0.5, 1.15, 0.24), offset = V(1.0, 1.35, 0), color = "steel" },
		{ name = "Poll", size = V(0.35, 0.5, 0.32), offset = V(-0.5, 1.35, 0), color = "steelDark" },
	},

	pickaxe_basic = {
		{ name = "Shaft", size = V(0.36, 3, 0.36), color = "trunk" },
		{ name = "Butt", size = V(0.44, 0.3, 0.44), offset = V(0, -1.6, 0), color = "trunkDark" },
		{ name = "Binding", size = V(0.5, 0.5, 0.5), offset = V(0, 1.1, 0), color = "trunkDark" },
		{ name = "HeadCore", size = V(0.8, 0.42, 0.4), offset = V(0, 1.42, 0), color = "steelDark" },
		{ name = "ArmL", size = V(1.0, 0.32, 0.32), offset = V(-0.85, 1.32, 0), rot = V(0, 0, 15), color = "steel" },
		{ name = "TipL", size = V(0.45, 0.24, 0.24), offset = V(-1.5, 1.12, 0), rot = V(0, 0, 15), color = "steelDark" },
		{ name = "ArmR", size = V(1.0, 0.32, 0.32), offset = V(0.85, 1.32, 0), rot = V(0, 0, -15), color = "steel" },
		{ name = "TipR", size = V(0.45, 0.24, 0.24), offset = V(1.5, 1.12, 0), rot = V(0, 0, -15), color = "steelDark" },
	},

	-- ---- armor (paper-doll gear; thumbnails + drops, never held) ------------

	helmet_leather = {
		{ name = "Skull", size = V(1.2, 0.7, 1.2), color = "leather" },
		{ name = "Top", size = V(0.9, 0.35, 0.9), offset = V(0, 0.5, 0), color = "leather" },
		{ name = "Brow", size = V(1.3, 0.3, 1.3), offset = V(0, -0.4, 0), color = "leatherDark" },
		{ name = "RivetL", size = V(0.14, 0.14, 0.14), offset = V(-0.62, -0.4, 0), color = "steelDark" },
		{ name = "RivetR", size = V(0.14, 0.14, 0.14), offset = V(0.62, -0.4, 0), color = "steelDark" },
	},

	chest_leather = {
		{ name = "Torso", size = V(1.4, 1.6, 0.7), color = "leather" },
		{ name = "ShoulderL", size = V(0.5, 0.35, 0.75), offset = V(-0.85, 0.7, 0), color = "leatherDark" },
		{ name = "ShoulderR", size = V(0.5, 0.35, 0.75), offset = V(0.85, 0.7, 0), color = "leatherDark" },
		{ name = "Lacing", size = V(0.2, 1.4, 0.1), offset = V(0, 0, -0.38), color = "leatherDark" },
		{ name = "Belt", size = V(1.44, 0.3, 0.74), offset = V(0, -0.75, 0), color = "leatherDark" },
		{ name = "Buckle", size = V(0.3, 0.3, 0.12), offset = V(0, -0.75, -0.36), color = "gold" },
	},

	gloves_leather = {
		{ name = "HandL", size = V(0.55, 0.75, 0.5), color = "leather" },
		{ name = "CuffL", size = V(0.65, 0.3, 0.6), offset = V(0, 0.45, 0), color = "leatherDark" },
		{ name = "ThumbL", size = V(0.2, 0.3, 0.2), offset = V(-0.32, -0.05, 0), color = "leather" },
		{ name = "HandR", size = V(0.55, 0.75, 0.5), offset = V(1.05, 0, 0), color = "leather" },
		{ name = "CuffR", size = V(0.65, 0.3, 0.6), offset = V(1.05, 0.45, 0), color = "leatherDark" },
		{ name = "ThumbR", size = V(0.2, 0.3, 0.2), offset = V(1.37, -0.05, 0), color = "leather" },
	},

	legs_leather = {
		{ name = "Waist", size = V(1.3, 0.5, 0.7), color = "leather" },
		{ name = "Belt", size = V(1.34, 0.24, 0.74), offset = V(0, 0.3, 0), color = "leatherDark" },
		{ name = "Buckle", size = V(0.28, 0.2, 0.1), offset = V(0, 0.3, -0.38), color = "gold" },
		{ name = "LegL", size = V(0.55, 1.4, 0.6), offset = V(-0.35, -0.9, 0), color = "leather" },
		{ name = "LegR", size = V(0.55, 1.4, 0.6), offset = V(0.35, -0.9, 0), color = "leather" },
		{ name = "KneeL", size = V(0.6, 0.3, 0.65), offset = V(-0.35, -1.0, 0), color = "leatherDark" },
		{ name = "KneeR", size = V(0.6, 0.3, 0.65), offset = V(0.35, -1.0, 0), color = "leatherDark" },
	},

	boots_leather = {
		{ name = "ShaftL", size = V(0.5, 0.9, 0.55), color = "leather" },
		{ name = "FootL", size = V(0.5, 0.35, 0.9), offset = V(0, -0.6, -0.25), color = "leatherDark" },
		{ name = "CuffL", size = V(0.6, 0.25, 0.65), offset = V(0, 0.45, 0), color = "leatherDark" },
		{ name = "ShaftR", size = V(0.5, 0.9, 0.55), offset = V(0.95, 0, 0), color = "leather" },
		{ name = "FootR", size = V(0.5, 0.35, 0.9), offset = V(0.95, -0.6, -0.25), color = "leatherDark" },
		{ name = "CuffR", size = V(0.6, 0.25, 0.65), offset = V(0.95, 0.45, 0), color = "leatherDark" },
	},

	-- ---- rings (tiny: they live in 1x1 tiles) --------------------------------

	ring_vitality = {
		{ name = "BandBottom", size = V(0.5, 0.1, 0.16), color = "gold" },
		{ name = "BandL", size = V(0.1, 0.4, 0.16), offset = V(-0.2, 0.2, 0), color = "gold" },
		{ name = "BandR", size = V(0.1, 0.4, 0.16), offset = V(0.2, 0.2, 0), color = "gold" },
		{ name = "BandTop", size = V(0.5, 0.1, 0.16), offset = V(0, 0.4, 0), color = "gold" },
		{ name = "Gem", size = V(0.24, 0.24, 0.24), offset = V(0, 0.55, 0), rot = V(0, 45, 45), color = "ruby", material = Enum.Material.Neon },
	},

	ring_focus = {
		{ name = "BandBottom", size = V(0.5, 0.1, 0.16), color = "steel" },
		{ name = "BandL", size = V(0.1, 0.4, 0.16), offset = V(-0.2, 0.2, 0), color = "steel" },
		{ name = "BandR", size = V(0.1, 0.4, 0.16), offset = V(0.2, 0.2, 0), color = "steel" },
		{ name = "BandTop", size = V(0.5, 0.1, 0.16), offset = V(0, 0.4, 0), color = "steel" },
		{ name = "Gem", size = V(0.24, 0.24, 0.24), offset = V(0, 0.55, 0), rot = V(0, 45, 45), color = "sapphire", material = Enum.Material.Neon },
	},

	-- ---- trait test gear (Phase A) -------------------------------------------

	ring_brawler = {
		{ name = "BandBottom", size = V(0.5, 0.1, 0.16), color = "steelDark" },
		{ name = "BandL", size = V(0.1, 0.4, 0.16), offset = V(-0.2, 0.2, 0), color = "steelDark" },
		{ name = "BandR", size = V(0.1, 0.4, 0.16), offset = V(0.2, 0.2, 0), color = "steelDark" },
		{ name = "BandTop", size = V(0.5, 0.1, 0.16), offset = V(0, 0.4, 0), color = "steelDark" },
		{ name = "Gem", size = V(0.28, 0.28, 0.28), offset = V(0, 0.55, 0), rot = V(0, 45, 45), color = "ruby", material = Enum.Material.Neon },
	},

	ring_lynx = {
		{ name = "BandBottom", size = V(0.5, 0.1, 0.16), color = "gold" },
		{ name = "BandL", size = V(0.1, 0.4, 0.16), offset = V(-0.2, 0.2, 0), color = "gold" },
		{ name = "BandR", size = V(0.1, 0.4, 0.16), offset = V(0.2, 0.2, 0), color = "gold" },
		{ name = "BandTop", size = V(0.5, 0.1, 0.16), offset = V(0, 0.4, 0), color = "gold" },
		{ name = "Gem", size = V(0.24, 0.24, 0.24), offset = V(0, 0.55, 0), rot = V(0, 45, 45), color = "gold", material = Enum.Material.Neon },
		{ name = "Pupil", size = V(0.1, 0.26, 0.1), offset = V(0, 0.55, -0.1), color = "ink" },
	},

	helmet_bastion = {
		{ name = "Skull", size = V(1.2, 0.7, 1.2), color = "steel" },
		{ name = "Top", size = V(0.9, 0.35, 0.9), offset = V(0, 0.5, 0), color = "steelDark" },
		{ name = "Crest", size = V(0.2, 0.55, 1.1), offset = V(0, 0.65, 0), color = "gold" },
		{ name = "Brow", size = V(1.3, 0.3, 1.3), offset = V(0, -0.4, 0), color = "steelDark" },
		{ name = "NoseGuard", size = V(0.22, 0.5, 0.16), offset = V(0, -0.6, -0.62), color = "steelDark" },
	},

	sword_duelist = {
		{ name = "Grip", size = V(0.28, 1.1, 0.28), color = "leatherDark" },
		{ name = "Pommel", size = V(0.4, 0.3, 0.4), offset = V(0, -0.7, 0), rot = V(0, 45, 0), color = "gold" },
		{ name = "Guard", size = V(1.1, 0.18, 0.4), offset = V(0, 0.62, 0), color = "gold" },
		{ name = "RingGuard", size = V(0.5, 0.4, 0.14), offset = V(0, 0.35, -0.2), color = "gold" },
		{ name = "Blade", size = V(0.4, 2.9, 0.13), offset = V(0, 2.15, 0), color = "steel" },
		{ name = "Tip", size = V(0.24, 0.55, 0.11), offset = V(0, 3.85, 0), color = "steel" },
	},

	chest_colossus = {
		{ name = "Torso", size = V(1.5, 1.7, 0.8), color = "steel" },
		{ name = "ShoulderL", size = V(0.6, 0.45, 0.85), offset = V(-0.95, 0.75, 0), color = "steelDark" },
		{ name = "ShoulderR", size = V(0.6, 0.45, 0.85), offset = V(0.95, 0.75, 0), color = "steelDark" },
		{ name = "Plate", size = V(0.9, 1.0, 0.16), offset = V(0, 0.2, -0.42), color = "steelDark" },
		{ name = "Belt", size = V(1.54, 0.32, 0.84), offset = V(0, -0.8, 0), color = "leatherDark" },
		{ name = "Buckle", size = V(0.34, 0.34, 0.12), offset = V(0, -0.8, -0.42), color = "gold" },
	},

	boots_evader = {
		{ name = "ShaftL", size = V(0.45, 0.85, 0.5), color = "leaf" },
		{ name = "FootL", size = V(0.45, 0.3, 0.85), offset = V(0, -0.55, -0.25), color = "leafDark" },
		{ name = "WingL", size = V(0.12, 0.4, 0.3), offset = V(-0.28, 0.35, 0.1), rot = V(0, 0, -20), color = "leafLight" },
		{ name = "ShaftR", size = V(0.45, 0.85, 0.5), offset = V(0.9, 0, 0), color = "leaf" },
		{ name = "FootR", size = V(0.45, 0.3, 0.85), offset = V(0.9, -0.55, -0.25), color = "leafDark" },
		{ name = "WingR", size = V(0.12, 0.4, 0.3), offset = V(1.18, 0.35, 0.1), rot = V(0, 0, 20), color = "leafLight" },
	},

	emblem_pyromancer = {
		{ name = "BandBottom", size = V(0.5, 0.1, 0.16), color = "gold" },
		{ name = "BandL", size = V(0.1, 0.4, 0.16), offset = V(-0.2, 0.2, 0), color = "gold" },
		{ name = "BandR", size = V(0.1, 0.4, 0.16), offset = V(0.2, 0.2, 0), color = "gold" },
		{ name = "BandTop", size = V(0.5, 0.1, 0.16), offset = V(0, 0.4, 0), color = "gold" },
		{ name = "Flame", shape = "Ball", size = V(0.3, 0.42, 0.3), offset = V(0, 0.6, 0), color = "ruby", material = Enum.Material.Neon },
	},

	emblem_berserker = {
		{ name = "BandBottom", size = V(0.5, 0.1, 0.16), color = "trunkDark" },
		{ name = "BandL", size = V(0.1, 0.4, 0.16), offset = V(-0.2, 0.2, 0), color = "trunkDark" },
		{ name = "BandR", size = V(0.1, 0.4, 0.16), offset = V(0.2, 0.2, 0), color = "trunkDark" },
		{ name = "BandTop", size = V(0.5, 0.1, 0.16), offset = V(0, 0.4, 0), color = "trunkDark" },
		{ name = "Spike", shape = "Wedge", size = V(0.2, 0.4, 0.24), offset = V(0, 0.6, 0), color = "ruby", material = Enum.Material.Neon },
	},

	-- ---- resources (inventory thumbnails, ground drops) --------------------

	wood = {
		{ name = "LogA", shape = "Cylinder", size = V(2.2, 0.7, 0.7), color = "trunk", rot = V(0, 15, 0) },
		{ name = "LogB", shape = "Cylinder", size = V(1.9, 0.6, 0.6), offset = V(0.1, 0.55, 0.1), rot = V(0, -25, 0), color = "trunkDark" },
	},

	stone = {
		{ name = "ChunkA", size = V(1.4, 1.0, 1.2), rot = V(6, 25, -4), color = "stone" },
		{ name = "ChunkB", size = V(0.9, 0.7, 0.8), offset = V(0.6, 0.35, -0.3), rot = V(-10, -35, 8), color = "stoneDark" },
		{ name = "ChunkC", size = V(0.6, 0.5, 0.6), offset = V(-0.6, 0.3, 0.4), rot = V(0, 50, 12), color = "stoneLight" },
	},

	slime_goo = {
		{ name = "BlobA", shape = "Ball", size = V(1.1, 1.1, 1.1), color = "slime", transparency = 0.25 },
		{ name = "BlobB", shape = "Ball", size = V(0.7, 0.7, 0.7), offset = V(0.45, 0.3, 0.15), color = "slime", transparency = 0.25 },
		{ name = "BlobC", shape = "Ball", size = V(0.5, 0.5, 0.5), offset = V(-0.4, 0.35, -0.2), color = "slime", transparency = 0.25 },
	},

	goblin_ear = {
		{ name = "EarBase", size = V(0.45, 0.6, 0.25), rot = V(0, 0, 20), color = "goblin" },
		{ name = "EarTip", shape = "Wedge", size = V(0.25, 0.7, 0.45), offset = V(-0.25, 0.55, 0), rot = V(0, 0, 30), color = "goblin" },
		{ name = "EarInner", size = V(0.24, 0.35, 0.28), offset = V(0.05, -0.05, 0), rot = V(0, 0, 20), color = "goblinDark" },
	},

	-- ---- crafting outputs (quick placeholders, swap out later) ------------

	crafting_table = {
		{ name = "Top", size = V(1.6, 0.18, 1.0), color = "trunk" },
		{ name = "LegA", size = V(0.16, 0.7, 0.16), offset = V(-0.65, -0.44, -0.35), color = "trunkDark" },
		{ name = "LegB", size = V(0.16, 0.7, 0.16), offset = V(0.65, -0.44, -0.35), color = "trunkDark" },
		{ name = "LegC", size = V(0.16, 0.7, 0.16), offset = V(-0.65, -0.44, 0.35), color = "trunkDark" },
		{ name = "LegD", size = V(0.16, 0.7, 0.16), offset = V(0.65, -0.44, 0.35), color = "trunkDark" },
	},

	torch = {
		{ name = "Handle", size = V(0.16, 1.0, 0.16), color = "trunkDark" },
		{ name = "Flame", shape = "Ball", size = V(0.34, 0.34, 0.34), offset = V(0, 0.6, 0), color = "gold", material = Enum.Material.Neon },
	},

	arrow = {
		{ name = "Shaft", size = V(0.08, 1.4, 0.08), color = "trunk" },
		{ name = "Head", shape = "Wedge", size = V(0.1, 0.28, 0.1), offset = V(0, 0.84, 0), color = "steel" },
	},

	acampada = {
		{ name = "Grip", size = V(0.3, 1.0, 0.3), color = "trunkDark" },
		{ name = "Bundle", shape = "Cylinder", size = V(1.0, 0.55, 0.55), offset = V(0, 0.7, 0), rot = V(0, 0, 90), color = "trunk" },
		{ name = "Strap", size = V(1.06, 0.14, 0.6), offset = V(0, 0.7, 0), color = "leatherDark" },
	},
	cofre_campamento = {
		{ name = "Grip", size = V(0.9, 0.7, 0.6), color = "trunk" },
		{ name = "Lid", size = V(0.94, 0.18, 0.64), offset = V(0, 0.44, 0), color = "trunkDark" },
		{ name = "Band", size = V(0.98, 0.1, 0.68), offset = V(0, 0.1, 0), color = "steelDark" },
		{ name = "Lock", size = V(0.14, 0.14, 0.1), offset = V(0, 0.36, -0.34), color = "gold" },
	},
	carpa_campamento = {
		{ name = "Grip", size = V(0.3, 1.0, 0.3), color = "trunkDark" },
		{ name = "PoleTop", shape = "Cylinder", size = V(0.9, 0.12, 0.12), offset = V(0, 0.65, 0), rot = V(0, 0, 90), color = "trunk" },
		{ name = "Canvas", shape = "Wedge", size = V(0.8, 0.6, 0.9), offset = V(0, 0.35, 0), rot = V(0, 90, 0), color = "leather" },
	},
}

function ItemModels.get(itemId)
	return ItemModels.defs[itemId]
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Builds an anchored display model at the origin (thumbnails, drops).
function ItemModels.build(itemId)
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local customModel = assets and assets:FindFirstChild(itemId)
	if customModel then
		local clone = customModel:Clone()
		if clone:IsA("Model") then
			if not clone.PrimaryPart then
				clone.PrimaryPart = clone:FindFirstChild("Handle") or clone:FindFirstChildOfClass("BasePart")
			end
			clone:PivotTo(CFrame.new())
		elseif clone:IsA("BasePart") then
			clone.CFrame = CFrame.new()
		end
		return clone
	end

	local specs = ItemModels.defs[itemId]
	if not specs then
		return nil
	end
	return ArtKit.build(itemId, CFrame.new(), specs)
end

-- Fills a ViewportFrame with the item's model, auto-framed by its bounding
-- box. Clears any previous preview. Returns true if the item has a model.
function ItemModels.preview(viewport, itemId)
	viewport:ClearAllChildren()
	local model = itemId and ItemModels.build(itemId)
	if not model then
		return false
	end
	model.Parent = viewport

	local camera = Instance.new("Camera")
	camera.FieldOfView = 40
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	local boundsCFrame, boundsSize = model:GetBoundingBox()
	local center = boundsCFrame.Position
	local distance = boundsSize.Magnitude * 1.5 + 0.5
	-- Slightly above and to the right, looking at the center.
	camera.CFrame = CFrame.lookAt(center + Vector3.new(0.45, 0.3, 1).Unit * distance, center)
	return true
end

return ItemModels
