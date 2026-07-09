-- Class definitions (MVP pass: passive stat multipliers only, no active
-- abilities yet). MUST stay in sync with backend/src/classes.js (class ids
-- and the "start everyone at level 1" default only — the multipliers below
-- are Roblox-only, the backend never needs them).
--
-- A player has ONE active class at a time (`currentClass`) but keeps a
-- separate level/xp track per class in `classLevels` (see PlayerService),
-- so switching classes doesn't erase progress on the others.

local Classes = {}

Classes.defs = {
	knight = {
		id = "knight",
		name = "Caballero",
		description = "Mucha vida y buena defensa. Fuerte cuerpo a cuerpo, débil a distancia.",
		hpMult = 1.35,
		maxManaMult = 0.60,
		manaRegenMult = 0.60,
		meleeDamageMult = 1.20,
		rangedDamageMult = 0.85, -- physical ranged (bow)
		magicDamageMult = 0.70, -- magic ranged (staff)
		damageTakenMult = 0.85, -- takes 15% less damage
		walkSpeedMult = 1.00,
		critChanceBonus = 0.00,
	},
	archer = {
		id = "archer",
		name = "Arquero",
		description = "Rápido y preciso a distancia con arco. Frágil cuerpo a cuerpo.",
		hpMult = 0.90,
		maxManaMult = 0.80,
		manaRegenMult = 0.80,
		meleeDamageMult = 0.80,
		rangedDamageMult = 1.35,
		magicDamageMult = 0.85,
		damageTakenMult = 1.05,
		walkSpeedMult = 1.10,
		critChanceBonus = 0.10,
	},
	mage = {
		id = "mage",
		name = "Mago",
		description = "Maná abundante y hechizos poderosos. Muy frágil.",
		hpMult = 0.80,
		maxManaMult = 1.75,
		manaRegenMult = 1.50,
		meleeDamageMult = 0.65,
		rangedDamageMult = 0.90,
		magicDamageMult = 1.45,
		damageTakenMult = 1.15,
		walkSpeedMult = 0.95,
		critChanceBonus = 0.05,
	},
	cleric = {
		id = "cleric",
		name = "Clérigo",
		description = "Magia curativa y de soporte. El corazón de toda party.",
		hpMult = 1.05,
		maxManaMult = 1.40,
		manaRegenMult = 1.25,
		meleeDamageMult = 0.85,
		rangedDamageMult = 0.80,
		magicDamageMult = 1.10,
		damageTakenMult = 0.95,
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

-- Damage multiplier for a given damage kind ("melee" | "physical" | "magic").
function Classes.damageMult(classDef, kind)
	if kind == "melee" then
		return classDef.meleeDamageMult
	elseif kind == "magic" then
		return classDef.magicDamageMult
	end
	return classDef.rangedDamageMult -- "physical" (bow) and any other ranged fallback
end

return Classes
