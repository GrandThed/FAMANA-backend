-- Pestaña de crafteos. Es 100% data driven, no está en el backend del server
-- Los items crafteados sí deben existir en backend/content/items.json y shared/Items.lua, no es necesario guardar las recetas allá
--
-- así se crean las recetas:
-- Recipe {
--   id:          string            -- also used as the craft request id
--   name:        string
--   result:      { itemId, quantity }
--   ingredients: { { itemId, quantity }, ... }
--   station:     string           -- nil = si no se aclara station, se puede craftear desde cualquier lado;
--
-- Add a recipe here (+ its output in shared/Items.lua and
-- backend/content/items.json if it's a new item) — CraftingService and
-- CraftUI are both fully data-driven off this list.

local Recipes = {}

Recipes.defs = {
	crafting_table = {
		id = "crafting_table",
		name = "Crafting Table",
		result = { itemId = "crafting_table", quantity = 1 },
		ingredients = {
			{ itemId = "wood", quantity = 15 },
		},
	},
	torch = {
		id = "torch",
		name = "Torch",
		result = { itemId = "torch", quantity = 1 },
		ingredients = {
			{ itemId = "wood", quantity = 3 },
			{ itemId = "slime_goo", quantity = 1 },
		},
		station = "crafting_table",
	},
	arrow = {
		id = "arrow",
		name = "Arrows",
		result = { itemId = "arrow", quantity = 4 },
		ingredients = {
			{ itemId = "wood", quantity = 1 },
			{ itemId = "stone", quantity = 1 },
		},
		station = "crafting_table",
	},
	simple_forge = {
		id = "simple_forge",
		name = "Forja Sencilla",
		result = { itemId = "simple_forge", quantity = 1 },
		ingredients = {
			{ itemId = "stone", quantity = 15 },
			{ itemId = "wood", quantity = 5 },
		},
	},
	copper_ingot = {
		id = "copper_ingot",
		name = "Copper Ingot",
		result = { itemId = "copper_ingot", quantity = 1 },
		ingredients = {
			{ itemId = "copper_ore", quantity = 2 },
		},
		station = "simple_forge",
	},
	pickaxe_copper = {
		id = "pickaxe_copper",
		name = "Copper Pickaxe",
		result = { itemId = "pickaxe_copper", quantity = 1 },
		ingredients = {
			{ itemId = "copper_ingot", quantity = 3 },
			{ itemId = "wood", quantity = 2 },
		},
		station = "crafting_table",
	},
	iron_ingot = {
		id = "iron_ingot",
		name = "Iron Ingot",
		result = { itemId = "iron_ingot", quantity = 1 },
		ingredients = {
			{ itemId = "iron_ore", quantity = 2 },
		},
		station = "simple_forge",
	},
}

function Recipes.get(recipeId)
	return Recipes.defs[recipeId]
end

-- lista de recetas en el orden que se muestran en la UI de crafting
local order = { "crafting_table", "simple_forge", "torch", "arrow", "copper_ingot", "pickaxe_copper", "iron_ingot" }

function Recipes.list()
	local list = {}
	for _, id in ipairs(order) do
		local def = Recipes.defs[id]
		if def then
			table.insert(list, def)
		end
	end
	-- las recetas que no están en la lista de orden se agregan al final (no deberían existir igual)
	for id, def in pairs(Recipes.defs) do
		if not table.find(order, id) then
			table.insert(list, def)
		end
	end
	return list
end

return Recipes
