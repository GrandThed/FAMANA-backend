-- Item rarity tiers (docs/UI.md §5 — border, name-text and glow colors
-- escalate together; the Color3s mirror the design doc's Theme.Rarity 1:1).
-- Rarity is cosmetic AND mechanical:
--   * cosmetic — slot/tile borders, tooltip title + frame, drop labels all
--     tint with the tier (Common stays neutral, no glow).
--   * mechanical — rarity ramps BOTH axes of a roll (docs/TRAITS_V2.md §6):
--     CONCENTRATION (the main line carries mainShare × itemLevel points —
--     only a legendary's main line reaches the full item level, and the
--     convex trait ladders make concentration power) and BONUS points
--     (bonusPercent of the item level, ceil, min 1, arriving as side
--     lines). Commons smear points into a generalist; legendaries build
--     specialists. See Traits.roll.
--
-- Where an item's rarity lives:
--   * fixed items — optional `rarity` on the def (backend content/items.json
--     + the Items.lua mirror); absent means common.
--   * rolled drops — `meta.rarity`, rolled at drop time (weights below) and
--     persisted with the instance meta (backend sanitizeMeta whitelists it).
--
-- No requires here on purpose: Items and Traits both lean on this module.

local Rarity = {}

-- weight       — relative roll odds (Traits.roll).
-- bonusPercent — bonus trait points as a fraction of item level (ceil,
--                min 1 when > 0), delivered as side lines.
-- mainShare    — the main line's cap as a fraction of ITEM LEVEL (1.0 =
--                a legendary main line carries the full item level).
-- lines        — total line count the tier aims for (number, or {min,max}
--                rolled per drop); clamped so every line keeps ≥1 point.
Rarity.defs = {
	common = {
		id = "common",
		name = "Common",
		order = 1,
		color = Color3.fromRGB(106, 100, 88), -- border
		textColor = Color3.fromRGB(184, 178, 162),
		glowColor = Color3.fromRGB(154, 148, 132),
		hasGlow = false,
		weight = 50,
		bonusPercent = 0,
		mainShare = 0.40,
		lines = 4,
	},
	uncommon = {
		id = "uncommon",
		name = "Uncommon",
		order = 2,
		color = Color3.fromRGB(92, 138, 60),
		textColor = Color3.fromRGB(127, 176, 85),
		glowColor = Color3.fromRGB(92, 138, 60),
		hasGlow = true,
		weight = 28,
		bonusPercent = 0.05,
		mainShare = 0.60,
		lines = 3,
	},
	rare = {
		id = "rare",
		name = "Rare",
		order = 3,
		color = Color3.fromRGB(79, 143, 214),
		textColor = Color3.fromRGB(106, 164, 224),
		glowColor = Color3.fromRGB(60, 110, 168),
		hasGlow = true,
		weight = 14,
		bonusPercent = 0.10,
		mainShare = 0.70,
		lines = { 2, 3 },
	},
	epic = {
		id = "epic",
		name = "Epic",
		order = 4,
		color = Color3.fromRGB(167, 106, 214),
		textColor = Color3.fromRGB(196, 143, 240),
		glowColor = Color3.fromRGB(167, 106, 214),
		hasGlow = true,
		weight = 6,
		bonusPercent = 0.15,
		mainShare = 0.90,
		lines = { 2, 3 },
	},
	legendary = {
		id = "legendary",
		name = "Legendary",
		order = 5,
		color = Color3.fromRGB(232, 168, 58),
		textColor = Color3.fromRGB(240, 192, 96),
		glowColor = Color3.fromRGB(224, 160, 58),
		hasGlow = true,
		weight = 2,
		bonusPercent = 0.25,
		mainShare = 1.00,
		lines = { 2, 3 },
	},
}

Rarity.order = { "common", "uncommon", "rare", "epic", "legendary" }

Rarity.DEFAULT = "common"

function Rarity.get(rarityId)
	return Rarity.defs[rarityId]
end

function Rarity.isValid(rarityId)
	return Rarity.defs[rarityId] ~= nil
end

-- The rarity def of an item def alone (fixed items; absent = common).
function Rarity.forDef(itemDef)
	local id = itemDef and itemDef.rarity
	return Rarity.defs[id] or Rarity.defs[Rarity.DEFAULT]
end

-- The effective rarity def of an inventory entry / drop: rolled instance
-- meta overrides the def's fixed value (same precedence as Traits.entryInfo).
function Rarity.forEntry(entry, itemDef)
	local meta = entry and entry.meta
	if typeof(meta) == "table" and Rarity.defs[meta.rarity] then
		return Rarity.defs[meta.rarity]
	end
	return Rarity.forDef(itemDef)
end

local totalWeight = 0
for _, id in ipairs(Rarity.order) do
	totalWeight += Rarity.defs[id].weight
end

-- Weighted roll → a rarity def (used by Traits.roll for dropped gear).
function Rarity.roll()
	local pick = math.random() * totalWeight
	for _, id in ipairs(Rarity.order) do
		local def = Rarity.defs[id]
		pick -= def.weight
		if pick <= 0 then
			return def
		end
	end
	return Rarity.defs[Rarity.DEFAULT]
end

return Rarity
