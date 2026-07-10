-- Class definitions. Each class has a set of MULTIPLIERS applied on top of
-- shared, level-scaling base stat curves (below) to produce the six live
-- combat stats: HP, Mana, Armor, MR (magic resist), AD (attack damage) and
-- AP (ability power). MUST stay in sync with backend/src/classes.js (class
-- ids and the "start everyone at level 1" default only — the stat curves
-- and multipliers below are Roblox-only, the backend never needs them).
--
-- A player has ONE active class at a time (`currentClass`) but keeps a
-- separate level/xp track per class in `classLevels` (see PlayerService),
-- so switching classes doesn't erase progress on the others.
--
-- Combat model: AD/AP/Armor/MR are the ONLY source of outgoing damage and
-- incoming mitigation — weapons/spells no longer carry their own flat
-- damage (see EnemyService.computePlayerDamage). This is deliberate: the
-- plan is for equipment to eventually carry zero stats of its own, with all
-- power coming from class stats + traits.

local Classes = {}

-- Levels run 1..MAX_LEVEL (see Config.PlayerLeveling.maxLevel, which MUST
-- match this).
Classes.MAX_LEVEL = 20

-- ---- level-scaling base curves (class-independent) -------------------------
-- These produce a "base" value at a given level; each class then applies its
-- own multiplier on top (see Classes.statsAtLevel). All are linear per level.

local function baseHP(level)
	return 100 + 25 * (level - 1)
end

local function baseMana(level)
	return 50 + 8 * (level - 1)
end

local function baseArmor(level)
	return 10 + 5 * (level - 1)
end

local function baseMR(level)
	return 10 + 5 * (level - 1)
end

local function baseAD(level)
	return 8 + 2 * (level - 1)
end

local function baseAP(level)
	return 8 + 2 * (level - 1)
end

-- ---- class defs -------------------------------------------------------------
-- hpMult/manaMult/armorMult/mrMult/adMult/apMult scale the level curves
-- above. manaRegenMult, walkSpeedMult and critChanceBonus are flat,
-- class-only modifiers that don't scale with level.

Classes.defs = {
	knight = {
		id = "knight",
		name = "Caballero",
		description = "Mucha vida y buena defensa. Fuerte cuerpo a cuerpo, débil a distancia.",
		hpMult = 1.35,
		manaMult = 0.40,
		manaRegenMult = 0.60,
		armorMult = 1.4,
		mrMult = 0.7,
		adMult = 1.05,
		apMult = 0.30,
		walkSpeedMult = 1.00,
		critChanceBonus = 0.00,
	},
	archer = {
		id = "archer",
		name = "Arquero",
		description = "Rápido y preciso a distancia con arco. Frágil cuerpo a cuerpo.",
		hpMult = 1.0,
		manaMult = 0.7,
		manaRegenMult = 0.80,
		armorMult = 0.7,
		mrMult = 0.6,
		adMult = 1.35,
		apMult = 0.30,
		walkSpeedMult = 1.10,
		critChanceBonus = 0.10,
	},
	mage = {
		id = "mage",
		name = "Mago",
		description = "Maná abundante y hechizos poderosos. Muy frágil.",
		hpMult = 0.85,
		manaMult = 1.4,
		manaRegenMult = 1.50,
		armorMult = 0.4,
		mrMult = 1.3,
		adMult = 0.40,
		apMult = 1.3,
		walkSpeedMult = 0.95,
		critChanceBonus = 0.05,
	},
	cleric = {
		id = "cleric",
		name = "Clérigo",
		description = "Magia curativa y de soporte. El corazón de toda party.",
		hpMult = 1.05,
		manaMult = 1.1,
		manaRegenMult = 1.25,
		armorMult = 1.1,
		mrMult = 1.1,
		adMult = 0.5,
		apMult = 1.0,
		walkSpeedMult = 1.00,
		critChanceBonus = 0.00,
	},
}

-- Display order for UI pickers.
Classes.order = { "knight", "archer", "mage", "cleric" }

Classes.DEFAULT = "knight"

function Classes.isValid(id)
	return Classes.defs[id] ~= nil
end

-- Always returns a valid def (falls back to the default class).
function Classes.get(id)
	return Classes.defs[id] or Classes.defs[Classes.DEFAULT]
end

-- The six live combat stats for a class at a given level, level-curve *
-- class multiplier, rounded to the nearest integer. Levels are clamped to
-- [1, MAX_LEVEL].
function Classes.statsAtLevel(classDef, level)
	level = math.clamp(math.floor((level or 1) + 0.5), 1, Classes.MAX_LEVEL)

	local function round(n)
		return math.floor(n + 0.5)
	end

	return {
		hp = round(baseHP(level) * classDef.hpMult),
		mana = round(baseMana(level) * classDef.manaMult),
		armor = round(baseArmor(level) * classDef.armorMult),
		mr = round(baseMR(level) * classDef.mrMult),
		ad = round(baseAD(level) * classDef.adMult),
		ap = round(baseAP(level) * classDef.apMult),
	}
end

-- Damage mitigation fraction from an Armor/MR value (MOBA-style diminishing
-- returns curve): 0 stat = 0% mitigated, 100 stat = 50% mitigated, and so on.
function Classes.mitigation(stat)
	stat = math.max(stat or 0, 0)
	return stat / (stat + 100)
end

return Classes
