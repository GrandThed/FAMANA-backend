-- Class passives — ONE fixed trait per main class (Knight/Archer/Mage/
-- Cleric), independent of equipment. Unlike shared/Traits.lua (points come
-- from the equipped paper doll), these scale purely off the player's own
-- CLASS LEVEL (see ClassService.getLevel), at the same tier breakpoints as
-- the subclass unlock ladder: 1 / 5 / 10 / 15 / 20 (Classes.MAX_LEVEL).
--
-- Deliberately shaped like a shared/Traits.lua entry (id, name, icon, color,
-- description, `thresholds` = { {threshold, stats} }) so the client can
-- render it with the EXACT SAME hex-badge/tooltip code as an equipment
-- trait (see client/SpellTrackerUI.lua's class-passive entry) — visually
-- indistinguishable from a "real" trait, just always active (from level 1)
-- and keyed by class id instead of earning points from gear.
--
-- Each class has exactly one entry here. server/ClassPassiveService.lua
-- reads these and feeds them into the SAME stat hooks SynergyService uses
-- (EnemyService/EffectService/HealthService), so the two systems stack
-- additively without knowing about each other.
--
-- Stat keys (same shape as Traits.lua, only the ones actually used here):
--   damageTakenMult — multiplier on incoming damage (Knight)
--   crit            — added critical strike chance, fraction (Archer)
--   duration        — buff/ability duration bonus, fraction (Mage)
--   regen           — HP regen per second, as a fraction of max HP,
--                      always on, even in combat (Cleric)
-- Each class ALSO carries its GATHERING IDENTITY from level 5 up
-- (docs/TRAITS_V2.md §5 — how each class harvests the world; gear traits
-- like Prospector stack additively on top):
--   gatherYield — Knight: +% yield from natural resources (wood/stone/ore)
--   mobDrops    — Archer: +% drops from enemies (NEVER equipment)
--   craftDouble — Mage: chance a potion craft produces double
--                 (content-gated: waits on potion recipes)
--   herbYield   — Cleric: +% herb yield (content-gated: waits on herb
--                 nodes + the sickle tool)

local ClassPassives = {}

-- thresholds: { {level, stats} } — the highest level reached applies (same
-- "highest threshold wins" rule as Traits.activeStats).
ClassPassives.defs = {
	knight = {
		id = "oakskin",
		classId = "knight",
		name = "Oakskin",
		icon = "🛡️",
		color = Color3.fromRGB(150, 160, 190),
		description = "The Knight's natural armor: reduces all incoming damage.",
		thresholds = {
			{ 1, { damageTakenMult = 0.95 } }, -- -5%
			{ 5, { damageTakenMult = 0.91, gatherYield = 0.10 } }, -- -9%
			{ 10, { damageTakenMult = 0.87, gatherYield = 0.29 } }, -- -13%
			{ 15, { damageTakenMult = 0.83, gatherYield = 0.53 } }, -- -17%
			{ 20, { damageTakenMult = 0.78, gatherYield = 0.82 } }, -- -22%
		},
	},
	archer = {
		id = "hawk_eye",
		classId = "archer",
		name = "Hawk Eye",
		icon = "🦅",
		color = Color3.fromRGB(240, 190, 70),
		description = "The Archer's innate aim: bonus critical strike chance.",
		thresholds = {
			{ 1, { crit = 0.05 } },
			{ 5, { crit = 0.09, mobDrops = 0.10 } },
			{ 10, { crit = 0.13, mobDrops = 0.29 } },
			{ 15, { crit = 0.17, mobDrops = 0.53 } },
			{ 20, { crit = 0.22, mobDrops = 0.82 } },
		},
	},
	mage = {
		id = "arcane_mastery",
		classId = "mage",
		name = "Arcane Mastery",
		icon = "🔮",
		color = Color3.fromRGB(150, 130, 220),
		description = "The Mage sustains their own buffs and debuffs for longer.",
		thresholds = {
			{ 1, { duration = 0.08 } },
			{ 5, { duration = 0.15, craftDouble = 0.10 } },
			{ 10, { duration = 0.22, craftDouble = 0.29 } },
			{ 15, { duration = 0.30, craftDouble = 0.53 } },
			{ 20, { duration = 0.40, craftDouble = 0.82 } },
		},
	},
	cleric = {
		id = "vital_aura",
		classId = "cleric",
		name = "Vital Aura",
		icon = "✨",
		color = Color3.fromRGB(220, 110, 90),
		description = "The Cleric steadily regenerates health, even in combat.",
		thresholds = {
			{ 1, { regen = 0.010 } },
			{ 5, { regen = 0.015, herbYield = 0.10 } },
			{ 10, { regen = 0.020, herbYield = 0.29 } },
			{ 15, { regen = 0.025, herbYield = 0.53 } },
			{ 20, { regen = 0.035, herbYield = 0.82 } },
		},
	},
}

-- Display order for UI lists (same order as Classes.order).
ClassPassives.order = { "knight", "archer", "mage", "cleric" }

function ClassPassives.get(classId)
	return ClassPassives.defs[classId]
end

-- Stats of the highest threshold `level` reaches, or nil if the class has no
-- passive (shouldn't happen — every playable class has one) or level < 1.
-- Mirrors Traits.activeStats(traitId, points).
function ClassPassives.activeStats(classId, level)
	local def = ClassPassives.defs[classId]
	if not def then
		return nil
	end
	local stats
	for _, threshold in ipairs(def.thresholds) do
		if level >= threshold[1] then
			stats = threshold[2]
		end
	end
	return stats
end

-- The next threshold's level above the player's current level, or nil once
-- maxed. Mirrors Traits.nextThreshold(traitId, points).
function ClassPassives.nextThreshold(classId, level)
	local def = ClassPassives.defs[classId]
	if not def then
		return nil
	end
	for _, threshold in ipairs(def.thresholds) do
		if threshold[1] > level then
			return threshold[1]
		end
	end
	return nil
end

-- ---- labels (UI) --------------------------------------------------------------

local STAT_ORDER =
	{ "damageTakenMult", "crit", "duration", "regen", "gatherYield", "mobDrops", "craftDouble", "herbYield" }

local STAT_LABELS = {
	damageTakenMult = function(v)
		return ("-%d%% damage taken"):format(math.floor((1 - v) * 100 + 0.5))
	end,
	crit = function(v)
		return ("+%d%% crit chance"):format(math.floor(v * 100 + 0.5))
	end,
	duration = function(v)
		return ("+%d%% ability duration"):format(math.floor(v * 100 + 0.5))
	end,
	regen = function(v)
		return ("+%.1f%%/s HP regen"):format(v * 100)
	end,
	gatherYield = function(v)
		return ("+%d%% resource yield"):format(math.floor(v * 100 + 0.5))
	end,
	mobDrops = function(v)
		return ("+%d%% enemy drops"):format(math.floor(v * 100 + 0.5))
	end,
	craftDouble = function(v)
		return ("%d%% double brew"):format(math.floor(v * 100 + 0.5))
	end,
	herbYield = function(v)
		return ("+%d%% herb yield"):format(math.floor(v * 100 + 0.5))
	end,
}

function ClassPassives.statLabel(key, value)
	local format = STAT_LABELS[key]
	return format and format(value) or (key .. " " .. tostring(value))
end

-- One line for a class's active tier: "-13% damage taken" (each class's
-- thresholds only ever carry a single stat key, unlike equipment Traits, so
-- this is normally just that one label — written the same way for
-- consistency with Traits.tierLabel in case that ever changes).
function ClassPassives.tierLabel(stats)
	local parts = {}
	for _, key in ipairs(STAT_ORDER) do
		if stats[key] then
			table.insert(parts, ClassPassives.statLabel(key, stats[key]))
		end
	end
	return table.concat(parts, ", ")
end

return ClassPassives
