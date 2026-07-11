-- Item definitions. The source of truth is backend/content/items.json —
-- the server fetches GET /content at boot (ContentService) and overlays it
-- here via Items.apply; clients get the same payload through the ContentData
-- StringValue (ContentSync). The static table below is the fallback for
-- Studio playtests without HTTP and for backend outages, so keep it roughly
-- in sync — drift is warned about at overlay time, not fatal.
--
-- `size` is the grid footprint {width, height} in inventory cells.
-- Armor/rings carry a `slot` matching an EQUIPMENT_SLOTS entry.
-- `rarity` is an optional tier id from shared/Rarity.lua (absent = common);
-- rolled drops override it per instance via meta.rarity.

-- `warn` is a Roblox global; the fallback keeps this module runnable under
-- the headless Luau CLI (content overlay tests).
local warn = warn or print

local Items = {}

-- Version hash of the applied backend content; nil while on the fallback.
Items.contentVersion = nil

Items.defs = {
	sword_basic = {
		id = "sword_basic",
		name = "Basic Sword",
		flavor = "Every legend starts somewhere.",
		type = "weapon",
		weaponType = "melee",
		damageKind = "melee", -- read by the class system's damage multiplier
		stackable = false,
		maxStack = 1,
		damage = 10,
		reach = 10, -- studs the swing (and its focus/targeting) can connect
		size = { 1, 3 },
		-- Starter weapons carry 1 school point so a fresh player's first
		-- equip unlocks their first spell (schools are equipment-only).
		itemLevel = 1,
		traits = { berserker = 1 },
	},
	axe_basic = {
		id = "axe_basic",
		name = "Basic Axe",
		type = "tool",
		stackable = false,
		maxStack = 1,
		toolType = "axe",
		toolTier = 1,
		gatherPower = 1,
		reach = 8, -- gathering wants you up close to the node
		size = { 2, 3 },
	},
	axe_copper = {
		id = "axe_copper",
		name = "Copper Axe",
		flavor = "A keener edge — enough to bite into old, hardened trunks.",
		type = "tool",
		stackable = false,
		maxStack = 1,
		toolType = "axe",
		toolTier = 2,
		gatherPower = 1,
		reach = 8,
		size = { 2, 3 },
	},
	pickaxe_basic = {
		id = "pickaxe_basic",
		name = "Basic Pickaxe",
		type = "tool",
		stackable = false,
		maxStack = 1,
		toolType = "pickaxe",
		toolTier = 1,
		gatherPower = 1,
		reach = 8,
		size = { 2, 3 },
	},
	pickaxe_copper = {
		id = "pickaxe_copper",
		name = "Copper Pickaxe",
		flavor = "Heavier than the basic pick — enough bite to crack open an iron vein.",
		type = "tool",
		stackable = false,
		maxStack = 1,
		toolType = "pickaxe",
		toolTier = 2,
		gatherPower = 1,
		reach = 8,
		size = { 2, 3 },
	},
	sword_iron = {
		id = "sword_iron",
		name = "Iron Sword",
		flavor = "Honest iron, honestly sharpened.",
		type = "weapon",
		weaponType = "melee",
		damageKind = "melee",
		rarity = "uncommon",
		stackable = false,
		maxStack = 1,
		damage = 20,
		reach = 10,
		size = { 1, 3 },
	},
	staff_basic = {
		id = "staff_basic",
		name = "Magic Staff",
		type = "weapon",
		weaponType = "ranged",
		damageKind = "magic",
		stackable = false,
		maxStack = 1,
		damage = 15,
		reach = 60,
		manaCost = 25, -- mana spent per cast; blocked when mana is too low
		size = { 1, 4 },
		itemLevel = 1,
		traits = { pyromancer = 1 },
	},
	bow_basic = {
		id = "bow_basic",
		name = "Basic Bow",
		type = "weapon",
		weaponType = "ranged",
		damageKind = "physical", -- ranged but not magic: no mana cost
		stackable = false,
		maxStack = 1,
		damage = 12,
		reach = 55,
		size = { 1, 4 },
		itemLevel = 1,
		traits = { sniper = 1 },
	},
	wood = {
		id = "wood",
		name = "Wood",
		type = "resource",
		stackable = true,
		maxStack = 50,
		size = { 1, 1 },
	},
	hardwood = {
		id = "hardwood",
		name = "Hardwood",
		flavor = "Dense, old-growth timber — a basic axe just bounces off it.",
		type = "resource",
		stackable = true,
		maxStack = 50,
		size = { 1, 1 },
	},
	stone = {
		id = "stone",
		name = "Stone",
		type = "resource",
		stackable = true,
		maxStack = 50,
		size = { 1, 1 },
	},
	copper_ore = {
		id = "copper_ore",
		name = "Copper Ore",
		flavor = "A soft, ruddy vein — common enough near any rockface.",
		type = "resource",
		stackable = true,
		maxStack = 50,
		size = { 1, 1 },
	},
	copper_ingot = {
		id = "copper_ingot",
		name = "Copper Ingot",
		flavor = "Smelted at a forge until the ore gives up its impurities.",
		type = "resource",
		stackable = true,
		maxStack = 50,
		size = { 1, 1 },
	},
	iron_ore = {
		id = "iron_ore",
		name = "Iron Ore",
		flavor = "Tougher rock, and it takes a copper pick to crack it.",
		type = "resource",
		stackable = true,
		maxStack = 50,
		size = { 1, 1 },
	},
	iron_ingot = {
		id = "iron_ingot",
		name = "Iron Ingot",
		flavor = "Smelted at a forge until the ore gives up its impurities.",
		type = "resource",
		stackable = true,
		maxStack = 50,
		size = { 1, 1 },
	},
	slime_goo = {
		id = "slime_goo",
		name = "Slime Goo",
		type = "resource",
		stackable = true,
		maxStack = 50,
		size = { 1, 1 },
	},
	goblin_ear = {
		id = "goblin_ear",
		name = "Goblin Ear",
		type = "resource",
		stackable = true,
		maxStack = 50,
		size = { 1, 1 },
	},

	-- ---- crafting outputs (placeholders — see shared/Recipes.lua) ---------
	simple_forge = {
		id = "simple_forge",
		name = "Forja Sencilla",
		flavor = "Una estación de fundición portátil. Solo se puede plantar dentro de una Acampada activa — ver roblox/src/server/CampFurnitureService.lua.",
		type = "placeable",
		stackable = false,
		maxStack = 1,
		size = { 2, 2 },
	},
	acampada = {
		id = "acampada",
		name = "Acampada",
		flavor = "Se coloca en el mundo y crea una zona segura de respawn para tu party. Equipala y hacé click en el piso para plantarla — ver roblox/src/server/CampService.lua.",
		type = "placeable",
		stackable = false,
		maxStack = 1,
		size = { 2, 2 },
	},
	cofre_campamento = {
		id = "cofre_campamento",
		name = "Cofre de Campamento",
		flavor = "Un cofre de almacenamiento compartido. Solo se puede plantar dentro de una Acampada activa — ver roblox/src/server/CampFurnitureService.lua.",
		type = "placeable",
		stackable = false,
		maxStack = 1,
		size = { 2, 2 },
	},
	carpa_campamento = {
		id = "carpa_campamento",
		name = "Carpa de Campamento",
		flavor = "Mobiliario decorativo para tu Acampada. Solo se puede plantar dentro de una Acampada activa.",
		type = "placeable",
		stackable = false,
		maxStack = 1,
		size = { 2, 3 },
	},
	torch = {
		id = "torch",
		name = "Torch",
		type = "misc",
		stackable = true,
		maxStack = 50,
		size = { 1, 1 },
	},
	arrow = {
		id = "arrow",
		name = "Arrow",
		type = "misc",
		stackable = true,
		maxStack = 99,
		size = { 1, 1 },
	},

	-- ---- armor (paper-doll equipment; combat stats come later) -------------
	helmet_leather = {
		id = "helmet_leather",
		name = "Leather Helmet",
		flavor = "Smells of rain and old campfires.",
		type = "armor",
		slot = "head",
		stackable = false,
		maxStack = 1,
		size = { 2, 2 },
	},
	chest_leather = {
		id = "chest_leather",
		name = "Leather Tunic",
		flavor = "Boiled hide, stitched by hunters of the low road.",
		type = "armor",
		slot = "chest",
		stackable = false,
		maxStack = 1,
		size = { 2, 3 },
	},
	gloves_leather = {
		id = "gloves_leather",
		name = "Leather Gloves",
		flavor = "Worn soft at the knuckles.",
		type = "armor",
		slot = "hands",
		stackable = false,
		maxStack = 1,
		size = { 2, 2 },
	},
	legs_leather = {
		id = "legs_leather",
		name = "Leather Leggings",
		flavor = "Patched more times than anyone admits.",
		type = "armor",
		slot = "legs",
		stackable = false,
		maxStack = 1,
		size = { 2, 2 },
	},
	boots_leather = {
		id = "boots_leather",
		name = "Leather Boots",
		flavor = "They know the way home.",
		type = "armor",
		slot = "feet",
		stackable = false,
		maxStack = 1,
		size = { 2, 2 },
	},

	-- ---- rings --------------------------------------------------------------
	ring_vitality = {
		id = "ring_vitality",
		name = "Ring of Vitality",
		type = "ring",
		slot = "ring",
		stackable = false,
		maxStack = 1,
		size = { 1, 1 },
	},
	ring_focus = {
		id = "ring_focus",
		name = "Ring of Focus",
		type = "ring",
		slot = "ring",
		stackable = false,
		maxStack = 1,
		size = { 1, 1 },
	},

	-- ---- trait test gear (Phase A: fixed traits on the def; see
	-- shared/Traits.lua + docs/TRAITS_AND_SPELLS.md). `itemLevel` gates the
	-- piece against the active class level (inert above it) and equals the
	-- sum of its trait points. ------------------------------------------------
	ring_brawler = {
		id = "ring_brawler",
		name = "Brawler Ring",
		type = "ring",
		slot = "ring",
		rarity = "uncommon",
		stackable = false,
		maxStack = 1,
		size = { 1, 1 },
		itemLevel = 2,
		traits = { brawler = 2 },
	},
	ring_lynx = {
		id = "ring_lynx",
		name = "Lynx Ring",
		type = "ring",
		slot = "ring",
		rarity = "uncommon",
		stackable = false,
		maxStack = 1,
		size = { 1, 1 },
		itemLevel = 3,
		traits = { lynx_eye = 3 },
	},
	helmet_bastion = {
		id = "helmet_bastion",
		name = "Bastion Helm",
		type = "armor",
		slot = "head",
		rarity = "rare",
		stackable = false,
		maxStack = 1,
		size = { 2, 2 },
		itemLevel = 5,
		traits = { bastion = 3, brawler = 2 },
	},
	sword_duelist = {
		id = "sword_duelist",
		name = "Duelist Sword",
		flavor = "It remembers every parry.",
		type = "weapon",
		weaponType = "melee",
		damageKind = "melee",
		rarity = "rare",
		stackable = false,
		maxStack = 1,
		damage = 15,
		reach = 10,
		size = { 1, 3 },
		itemLevel = 7,
		traits = { lynx_eye = 4, agile_hands = 3 },
	},
	chest_colossus = {
		id = "chest_colossus",
		name = "Colossus Chestplate",
		flavor = "Forged for shoulders that carry armies.",
		type = "armor",
		slot = "chest",
		rarity = "epic",
		stackable = false,
		maxStack = 1,
		size = { 2, 3 },
		itemLevel = 8,
		traits = { brawler = 5, bastion = 3 },
	},
	boots_evader = {
		id = "boots_evader",
		name = "Evader Boots",
		flavor = "Never quite where the blow lands.",
		type = "armor",
		slot = "feet",
		rarity = "epic",
		stackable = false,
		maxStack = 1,
		size = { 2, 2 },
		itemLevel = 9,
		traits = { evasion = 5, brawler = 4 },
	},

	-- School emblems: pure school-point items (TFT emblem fantasy) for
	-- testing the equipment-driven spell unlocks.
	emblem_pyromancer = {
		id = "emblem_pyromancer",
		name = "Pyromancer Emblem",
		type = "ring",
		slot = "ring",
		rarity = "epic",
		stackable = false,
		maxStack = 1,
		size = { 1, 1 },
		itemLevel = 5,
		traits = { pyromancer = 5 },
	},
	emblem_berserker = {
		id = "emblem_berserker",
		name = "Berserker Emblem",
		type = "ring",
		slot = "ring",
		rarity = "epic",
		stackable = false,
		maxStack = 1,
		size = { 1, 1 },
		itemLevel = 5,
		traits = { berserker = 5 },
	},
		-- ---- todos estos para abajo son items que se craftean
	crafting_table = {
		id = "crafting_table",
		name = "Crafting Table",
		flavor = "Solo se puede plantar dentro de una Acampada activa — ver roblox/src/server/CampFurnitureService.lua.",
		type = "placeable",
		stackable = false,
		maxStack = 1,
		size = { 2, 2 },
	},
	torch = {
		id = "torch",
		name = "Torch",
		type = "misc",
		stackable = true,
		maxStack = 50,
		size = { 1, 1 },
	},
	arrow = {
		id = "arrow",
		name = "Arrow",
		type = "misc",
		stackable = true,
		maxStack = 99,
		size = { 1, 1 },
	},
	emblem_sacerdote = {
		id = "emblem_sacerdote",
		name = "Sacerdote Emblem",
		type = "ring",
		slot = "ring",
		rarity = "epic",
		stackable = false,
		maxStack = 1,
		size = { 1, 1 },
		itemLevel = 5,
		traits = { sacerdote_luz = 5 },
	},
	emblem_vengador = {
		id = "emblem_vengador",
		name = "Vengador Emblem",
		type = "ring",
		slot = "ring",
		rarity = "epic",
		stackable = false,
		maxStack = 1,
		size = { 1, 1 },
		itemLevel = 5,
		traits = { vengador_sagrado = 5 },
	},
	emblem_oraculo = {
		id = "emblem_oraculo",
		name = "Oráculo Emblem",
		type = "ring",
		slot = "ring",
		rarity = "epic",
		stackable = false,
		maxStack = 1,
		size = { 1, 1 },
		itemLevel = 5,
		traits = { oraculo = 5 },
	},
}

-- Paper-doll equipment slots. A slot's index-1 is its `x` in the `equipment`
-- container (y = 0). MUST match backend EQUIPMENT_SLOTS order.
Items.EQUIPMENT_SLOTS = {
	"weapon",
	"offhand",
	"head",
	"chest",
	"hands",
	"legs",
	"feet",
	"back",
	"ring1",
	"ring2",
}

function Items.get(itemId)
	return Items.defs[itemId]
end

function Items.maxStackFor(itemId)
	local def = Items.defs[itemId]
	if not def then
		return 0
	end
	return def.stackable and def.maxStack or 1
end

-- Footprint (w, h) of an item as placed (swapped when rotated).
function Items.sizeFor(itemId, rotated)
	local def = Items.defs[itemId]
	local size = def and def.size or { 1, 1 }
	if rotated then
		return size[2], size[1]
	end
	return size[1], size[2]
end

-- Overlay backend-served content onto the local defs. Fetched defs replace
-- local ones wholesale; local-only defs survive (they keep Studio/offline
-- working) but get flagged as mirror drift. Returns true if applied.
function Items.apply(content)
	if type(content) ~= "table" or type(content.items) ~= "table" then
		return false
	end

	local fetched = {}
	for id, def in pairs(content.items) do
		Items.defs[id] = def
		fetched[id] = true
	end

	local localOnly = {}
	for id in pairs(Items.defs) do
		if not fetched[id] then
			table.insert(localOnly, id)
		end
	end
	if #localOnly > 0 then
		warn(
			"[Items] defs only in the Luau mirror, missing from backend content: "
				.. table.concat(localOnly, ", ")
		)
	end

	-- Slot order is persisted data (x index in the equipment container), so it
	-- is never overlaid — only verified against the backend's copy.
	if type(content.equipmentSlots) == "table" then
		for i, name in ipairs(Items.EQUIPMENT_SLOTS) do
			if content.equipmentSlots[i] ~= name then
				warn("[Items] EQUIPMENT_SLOTS mismatch at index " .. i .. " — fix the mirror!")
				break
			end
		end
	end

	Items.contentVersion = content.version
	return true
end

-- Whether an item def may sit in the given equipment slot.
function Items.slotAccepts(slotName, def)
	if not def then
		return false
	end
	if slotName == "weapon" or slotName == "offhand" then
		return def.type == "weapon" or def.type == "tool"
	end
	if slotName == "ring1" or slotName == "ring2" then
		return def.type == "ring"
	end
	if slotName == "back" then
		return def.type == "backpack"
	end
	return def.type == "armor" and def.slot == slotName
end

return Items