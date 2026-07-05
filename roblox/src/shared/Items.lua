-- Item definitions. The source of truth is backend/content/items.json —
-- the server fetches GET /content at boot (ContentService) and overlays it
-- here via Items.apply; clients get the same payload through the ContentData
-- StringValue (ContentSync). The static table below is the fallback for
-- Studio playtests without HTTP and for backend outages, so keep it roughly
-- in sync — drift is warned about at overlay time, not fatal.
--
-- `size` is the grid footprint {width, height} in inventory cells.
-- Armor/rings carry a `slot` matching an EQUIPMENT_SLOTS entry.

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
		type = "weapon",
		weaponType = "melee",
		stackable = false,
		maxStack = 1,
		damage = 10,
		reach = 10, -- studs the swing (and its focus/targeting) can connect
		size = { 1, 3 },
	},
	axe_basic = {
		id = "axe_basic",
		name = "Basic Axe",
		type = "tool",
		stackable = false,
		maxStack = 1,
		toolType = "axe",
		gatherPower = 1,
		reach = 8, -- gathering wants you up close to the node
		size = { 2, 3 },
	},
	pickaxe_basic = {
		id = "pickaxe_basic",
		name = "Basic Pickaxe",
		type = "tool",
		stackable = false,
		maxStack = 1,
		toolType = "pickaxe",
		gatherPower = 1,
		reach = 8,
		size = { 2, 3 },
	},
	sword_iron = {
		id = "sword_iron",
		name = "Iron Sword",
		type = "weapon",
		weaponType = "melee",
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
		stackable = false,
		maxStack = 1,
		damage = 15,
		reach = 60,
		manaCost = 25, -- mana spent per cast; blocked when mana is too low
		size = { 1, 4 },
	},
	wood = {
		id = "wood",
		name = "Wood",
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

	-- ---- armor (paper-doll equipment; combat stats come later) -------------
	helmet_leather = {
		id = "helmet_leather",
		name = "Leather Helmet",
		type = "armor",
		slot = "head",
		stackable = false,
		maxStack = 1,
		size = { 2, 2 },
	},
	chest_leather = {
		id = "chest_leather",
		name = "Leather Tunic",
		type = "armor",
		slot = "chest",
		stackable = false,
		maxStack = 1,
		size = { 2, 3 },
	},
	gloves_leather = {
		id = "gloves_leather",
		name = "Leather Gloves",
		type = "armor",
		slot = "hands",
		stackable = false,
		maxStack = 1,
		size = { 2, 2 },
	},
	legs_leather = {
		id = "legs_leather",
		name = "Leather Leggings",
		type = "armor",
		slot = "legs",
		stackable = false,
		maxStack = 1,
		size = { 2, 2 },
	},
	boots_leather = {
		id = "boots_leather",
		name = "Leather Boots",
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
