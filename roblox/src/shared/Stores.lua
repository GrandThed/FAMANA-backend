-- Store definitions (vendor trade lists). Source of truth is
-- backend/content/stores.json, overlaid at boot from GET /content the same
-- way as Items (see ContentService/ContentSync). The static table below is
-- the fallback for Studio-without-HTTP and backend outages.
--
-- Prices are gold per unit; a trade may be buy-only (no sellPrice),
-- sell-only (no buyPrice), or both. Vendor NPC placement lives in
-- server/VendorService — this module is economy data only.

-- `warn` is a Roblox global; the fallback keeps this module runnable under
-- the headless Luau CLI (content overlay tests).
local warn = warn or print

local Stores = {}

Stores.defs = {
	general_goods = {
		id = "general_goods",
		name = "General Goods",
		trades = {
			{ itemId = "sword_iron", buyPrice = 120, sellPrice = 40 },
			{ itemId = "helmet_leather", buyPrice = 40, sellPrice = 12 },
			{ itemId = "chest_leather", buyPrice = 60, sellPrice = 18 },
			{ itemId = "gloves_leather", buyPrice = 30, sellPrice = 9 },
			{ itemId = "legs_leather", buyPrice = 45, sellPrice = 13 },
			{ itemId = "boots_leather", buyPrice = 30, sellPrice = 9 },
			{ itemId = "ring_vitality", buyPrice = 150, sellPrice = 50 },
			{ itemId = "ring_focus", buyPrice = 150, sellPrice = 50 },
			{ itemId = "wood", sellPrice = 2 },
			{ itemId = "stone", sellPrice = 2 },
			{ itemId = "slime_goo", sellPrice = 3 },
			{ itemId = "goblin_ear", sellPrice = 5 },
		},
	},
}

function Stores.get(storeId)
	return Stores.defs[storeId]
end

-- The trade entry for an item in a store, or nil if the store doesn't
-- carry it.
function Stores.trade(storeId, itemId)
	local store = Stores.defs[storeId]
	if not store then
		return nil
	end
	for _, trade in ipairs(store.trades) do
		if trade.itemId == itemId then
			return trade
		end
	end
	return nil
end

-- Overlay backend-served store defs, same contract as Items.apply: fetched
-- stores replace local ones wholesale, local-only stores survive but get
-- flagged as mirror drift. Returns true if applied.
function Stores.apply(storeDefs)
	if type(storeDefs) ~= "table" then
		return false
	end

	local fetched = {}
	for id, def in pairs(storeDefs) do
		Stores.defs[id] = def
		fetched[id] = true
	end

	local localOnly = {}
	for id in pairs(Stores.defs) do
		if not fetched[id] then
			table.insert(localOnly, id)
		end
	end
	if #localOnly > 0 then
		warn(
			"[Stores] defs only in the Luau mirror, missing from backend content: "
				.. table.concat(localOnly, ", ")
		)
	end

	return true
end

return Stores
