-- Spell + subclass-school definitions (see docs/TRAITS_AND_SPELLS.md and the
-- "Rasgos" design board). Each class has up to three schools (subclasses);
-- a school grants active spells at level thresholds plus a scaling passive
-- (+% damage of a kind, or flat armor).
--
-- MVP unlock rule ("all schools" test mode): a player knows every implemented
-- spell of every school of their ACTIVE class whose unlock level they've
-- reached. Restricting to one chosen subclass later only means filtering
-- schoolsFor() by the player's pick — defs already carry their school.
--
-- Numbers here are demonstrative (like the board says) and made to be tuned.

local Spells = {}

-- Hotbar binds store spells as "spell:<id>" strings next to plain item ids.
Spells.BIND_PREFIX = "spell:"

-- Player attribute "SpellCd_<id>" holds the cooldown expiry on the server
-- clock (Workspace:GetServerTimeNow()), mirroring the Effect_<id> scheme.
Spells.cdAttributePrefix = "SpellCd_"

-- ---- schools (subclasses) ---------------------------------------------------
-- passive.stat: "magic" | "physical" (physical also boosts melee) | "armor".
-- passive.thresholds: { {level, value} } — highest reached level applies.
-- spells: { {id, level} } — actives granted at that class level.
-- familiars: invoker-only summon-count thresholds.

Spells.schools = {
	-- ---- Mage ---------------------------------------------------------------
	pyromancer = {
		id = "pyromancer",
		name = "Pyromancer",
		classIds = { "mage" },
		icon = "🔥",
		color = Color3.fromRGB(255, 120, 50),
		passive = {
			stat = "magic",
			thresholds = { { 1, 0.10 }, { 5, 0.20 }, { 10, 0.30 }, { 15, 0.42 }, { 20, 0.55 } },
		},
		spells = { { "fireball", 1 }, { "flame_wall", 10 }, { "supernova", 20 } },
	},
	arcanist = {
		id = "arcanist",
		name = "Arcanist",
		classIds = { "mage" },
		icon = "🔮",
		color = Color3.fromRGB(150, 90, 255),
		passive = {
			stat = "magic",
			thresholds = { { 1, 0.10 }, { 5, 0.15 }, { 10, 0.25 }, { 15, 0.35 }, { 20, 0.50 } },
		},
		spells = { { "arcane_missile", 1 }, { "arcane_rain", 10 }, { "arcane_storm", 20 } },
	},
	invoker = {
		id = "invoker",
		name = "Invoker",
		-- The board makes the summoner a mage subclass; the standalone
		-- summoner class shares it until that open question is settled.
		classIds = { "mage", "summoner" },
		icon = "👻",
		color = Color3.fromRGB(120, 220, 180),
		passive = {
			stat = "magic",
			thresholds = { { 1, 0.06 }, { 5, 0.12 }, { 10, 0.18 }, { 15, 0.25 }, { 20, 0.35 } },
		},
		-- Level 10 is the second familiar (see familiars below), level 15
		-- borrows Arcane Rain per the board.
		spells = { { "summon_familiar", 1 }, { "arcane_rain", 15 }, { "grand_familiar", 20 } },
		familiars = { { 1, 1 }, { 10, 2 } },
	},

	-- ---- Knight --------------------------------------------------------------
	berserker = {
		id = "berserker",
		name = "Berserker",
		classIds = { "knight" },
		icon = "🩸",
		color = Color3.fromRGB(220, 80, 60),
		passive = {
			stat = "physical",
			thresholds = { { 1, 0.10 }, { 5, 0.18 }, { 10, 0.28 }, { 15, 0.38 }, { 20, 0.50 } },
		},
		spells = { { "battle_cry", 1 }, { "savage_strike", 10 }, { "frenzy", 20 } },
	},
	sentinel = {
		id = "sentinel",
		name = "Sentinel",
		classIds = { "knight" },
		icon = "🛡️",
		color = Color3.fromRGB(120, 150, 200),
		passive = {
			stat = "armor",
			thresholds = { { 1, 8 }, { 5, 16 }, { 10, 24 }, { 15, 32 }, { 20, 42 } },
		},
		spells = { { "provoke", 1 }, { "steel_loyalty", 10 }, { "bulwark", 20 } },
	},
	justicar = {
		id = "justicar",
		name = "Justicar",
		classIds = { "knight" },
		icon = "⚖️",
		color = Color3.fromRGB(240, 200, 90),
		passive = {
			stat = "physical",
			thresholds = { { 1, 0.10 }, { 5, 0.15 }, { 10, 0.25 }, { 15, 0.30 }, { 20, 0.35 } },
		},
		spells = { { "stunning_strike", 1 }, { "judgment", 10 }, { "verdict", 20 } },
	},

	-- ---- Ranger (board is still sketchy: burst / CC / movement) ---------------
	sniper = {
		id = "sniper",
		name = "Sniper",
		classIds = { "archer" },
		icon = "🎯",
		color = Color3.fromRGB(90, 200, 90),
		spells = { { "deadeye_shot", 1 } },
	},
	trapper = {
		id = "trapper",
		name = "Trapper",
		classIds = { "archer" },
		icon = "🕸️",
		color = Color3.fromRGB(160, 130, 80),
		spells = { { "snare_trap", 1 } },
	},
	scout = {
		id = "scout",
		name = "Scout",
		classIds = { "archer" },
		icon = "💨",
		color = Color3.fromRGB(90, 210, 230),
		spells = { { "sprint", 1 } },
	},
}

-- Stable iteration/UI order.
Spells.schoolOrder = {
	"pyromancer", "arcanist", "invoker",
	"berserker", "sentinel", "justicar",
	"sniper", "trapper", "scout",
}

-- ---- spell defs ---------------------------------------------------------------
-- behavior: "projectile" | "zone" | "strike" | "aoe" | "buff" | "taunt" | "summon".
-- hotbarPriority orders the recommended loadout (lower = earlier slot).
-- implemented = false marks board placeholders that can't be cast yet.

Spells.defs = {
	-- ---- Pyromancer -----------------------------------------------------------
	fireball = {
		id = "fireball",
		name = "Fireball",
		school = "pyromancer",
		icon = "🔥",
		description = "Hurls a fireball that explodes on impact, splashing nearby enemies.",
		behavior = "projectile",
		damageKind = "magic",
		manaCost = 30,
		cooldown = 4,
		range = 50,
		damage = 18,
		splashRadius = 6,
		splashMult = 0.5,
		missile = { size = 1.4, color = Color3.fromRGB(255, 120, 50), speed = 70 },
		hotbarPriority = 10,
	},
	flame_wall = {
		id = "flame_wall",
		name = "Flame Wall",
		school = "pyromancer",
		icon = "🌋",
		description = "Raises a wall of fire in front of you that burns enemies standing in it.",
		behavior = "zone",
		damageKind = "magic",
		manaCost = 45,
		cooldown = 14,
		placement = "front",
		frontDistance = 9,
		box = { width = 14, depth = 4, height = 5 },
		duration = 6,
		tickInterval = 1,
		tickDamage = 8,
		color = Color3.fromRGB(255, 120, 50),
		hotbarPriority = 30,
	},
	supernova = {
		id = "supernova",
		name = "SuperNova",
		school = "pyromancer",
		icon = "💥",
		description = "Ultimate: a massive explosion around you.",
		behavior = "aoe",
		damageKind = "magic",
		manaCost = 80,
		cooldown = 60,
		radius = 14,
		damage = 65,
		color = Color3.fromRGB(255, 160, 60),
		hotbarPriority = 50,
	},

	-- ---- Arcanist ---------------------------------------------------------------
	arcane_missile = {
		id = "arcane_missile",
		name = "Arcane Missile",
		school = "arcanist",
		icon = "🔮",
		description = "A fast, cheap arcane bolt. Spammable.",
		behavior = "projectile",
		damageKind = "magic",
		manaCost = 14,
		cooldown = 1.2,
		range = 55,
		damage = 11,
		missile = { size = 0.9, color = Color3.fromRGB(150, 90, 255), speed = 110 },
		hotbarPriority = 20,
	},
	arcane_rain = {
		id = "arcane_rain",
		name = "Arcane Rain",
		school = "arcanist",
		icon = "🌠",
		description = "Rains arcane energy over the target area for a few seconds.",
		behavior = "zone",
		damageKind = "magic",
		manaCost = 50,
		cooldown = 16,
		placement = "target",
		range = 45,
		radius = 8,
		duration = 5,
		tickInterval = 1,
		tickDamage = 10,
		color = Color3.fromRGB(150, 90, 255),
		hotbarPriority = 31,
	},
	arcane_storm = {
		id = "arcane_storm",
		name = "Arcane Storm",
		school = "arcanist",
		icon = "🌀",
		description = "Ultimate: an enormous arcane storm over the target.",
		behavior = "zone",
		damageKind = "magic",
		manaCost = 80,
		cooldown = 60,
		placement = "target",
		range = 45,
		radius = 11,
		duration = 6,
		tickInterval = 1,
		tickDamage = 16,
		color = Color3.fromRGB(110, 60, 220),
		hotbarPriority = 51,
	},

	-- ---- Invoker -----------------------------------------------------------------
	summon_familiar = {
		id = "summon_familiar",
		name = "Summon Familiar",
		school = "invoker",
		icon = "👻",
		description = "Summons a familiar that follows you and attacks your enemies (two from level 10).",
		behavior = "summon",
		damageKind = "magic",
		manaCost = 40,
		cooldown = 20,
		summon = { variant = "familiar", duration = 60, damage = 6, shotEvery = 1.5, range = 30 },
		hotbarPriority = 40,
	},
	grand_familiar = {
		id = "grand_familiar",
		name = "Grand Familiar",
		school = "invoker",
		icon = "😈",
		description = "Ultimate: summons a far more aggressive grand familiar for a while.",
		behavior = "summon",
		damageKind = "magic",
		manaCost = 70,
		cooldown = 60,
		summon = { variant = "gran", duration = 30, damage = 15, shotEvery = 1.2, range = 35 },
		hotbarPriority = 52,
	},

	-- ---- Berserker ------------------------------------------------------------
	battle_cry = {
		id = "battle_cry",
		name = "Battle Cry",
		school = "berserker",
		icon = "📣",
		description = "A war cry that raises your physical damage for a few seconds.",
		behavior = "buff",
		manaCost = 18,
		cooldown = 15,
		effectId = "battle_cry",
		hotbarPriority = 30,
	},
	savage_strike = {
		id = "savage_strike",
		name = "Savage Strike",
		school = "berserker",
		icon = "💢",
		description = "A brutal melee blow.",
		behavior = "strike",
		damageKind = "melee",
		manaCost = 22,
		cooldown = 8,
		range = 9,
		damage = 35,
		hotbarPriority = 10,
	},
	frenzy = {
		id = "frenzy",
		name = "Frenzy",
		school = "berserker",
		icon = "🩸",
		description = "Ultimate: you go berserk — much more damage and speed.",
		behavior = "buff",
		manaCost = 35,
		cooldown = 60,
		effectId = "frenzy",
		hotbarPriority = 50,
	},

	-- ---- Sentinel ---------------------------------------------------------------
	provoke = {
		id = "provoke",
		name = "Provoke",
		school = "sentinel",
		icon = "😤",
		description = "Taunts nearby enemies into attacking you, and you brace for the hits.",
		behavior = "taunt",
		manaCost = 12,
		cooldown = 10,
		radius = 18,
		tauntDuration = 6,
		effectId = "on_guard",
		hotbarPriority = 35,
	},
	steel_loyalty = {
		id = "steel_loyalty",
		name = "Steel Loyalty",
		school = "sentinel",
		icon = "🛡️",
		description = "Reinforced defense for you and nearby allies.",
		behavior = "buff",
		manaCost = 25,
		cooldown = 20,
		effectId = "steel_loyalty",
		allyRadius = 15,
		hotbarPriority = 36,
	},
	bulwark = {
		id = "bulwark",
		name = "Bulwark",
		school = "sentinel",
		icon = "🏰",
		description = "Ultimate: you and your allies take half damage for a few seconds.",
		behavior = "buff",
		manaCost = 35,
		cooldown = 60,
		effectId = "bulwark",
		allyRadius = 20,
		hotbarPriority = 55,
	},

	-- ---- Justicar ------------------------------------------------------------------
	stunning_strike = {
		id = "stunning_strike",
		name = "Stunning Strike",
		school = "justicar",
		icon = "💫",
		description = "A blow that stuns the target for a moment.",
		behavior = "strike",
		damageKind = "melee",
		manaCost = 18,
		cooldown = 10,
		range = 9,
		damage = 20,
		stunDuration = 1.5,
		hotbarPriority = 11,
	},
	judgment = {
		id = "judgment",
		name = "Judgment",
		school = "justicar",
		icon = "⚖️",
		description = "Punishes every enemy around you and briefly stuns them.",
		behavior = "aoe",
		damageKind = "physical",
		manaCost = 30,
		cooldown = 18,
		radius = 10,
		damage = 30,
		stunDuration = 1,
		color = Color3.fromRGB(240, 200, 90),
		hotbarPriority = 32,
	},
	verdict = {
		id = "verdict",
		name = "Verdict",
		school = "justicar",
		icon = "🔨",
		description = "Ultimate: a devastating blow that takes the target out of the fight.",
		behavior = "strike",
		damageKind = "physical",
		manaCost = 45,
		cooldown = 60,
		range = 12,
		damage = 80,
		stunDuration = 2.5,
		hotbarPriority = 53,
	},

	-- ---- Ranger (proposals — the board only names the fantasy) --------------------
	deadeye_shot = {
		id = "deadeye_shot",
		name = "Deadeye Shot",
		school = "sniper",
		icon = "🎯",
		description = "A precision shot at your locked target. Requires a focused target.",
		behavior = "projectile",
		damageKind = "physical",
		manaCost = 15,
		cooldown = 6,
		range = 70,
		damage = 30,
		requiresFocus = true,
		missile = { size = 0.6, color = Color3.fromRGB(120, 85, 45), speed = 140 },
		hotbarPriority = 10,
	},
	snare_trap = {
		id = "snare_trap",
		name = "Snare Trap",
		school = "trapper",
		icon = "🕸️",
		description = "Lays a snare zone in front of you that slows enemies crossing it.",
		behavior = "zone",
		damageKind = "physical",
		manaCost = 20,
		cooldown = 12,
		placement = "front",
		frontDistance = 6,
		radius = 4,
		duration = 15,
		tickInterval = 0.5,
		tickDamage = 0,
		slow = { mult = 0.45, duration = 1.5 },
		color = Color3.fromRGB(160, 130, 80),
		hotbarPriority = 30,
	},
	sprint = {
		id = "sprint",
		name = "Sprint",
		school = "scout",
		icon = "💨",
		description = "You run much faster for a few seconds.",
		behavior = "buff",
		manaCost = 12,
		cooldown = 12,
		effectId = "sprint",
		hotbarPriority = 40,
	},
}

-- ---- lookups -------------------------------------------------------------------

function Spells.get(spellId)
	return Spells.defs[spellId]
end

function Spells.getSchool(schoolId)
	return Spells.schools[schoolId]
end

-- Schools available to a class, in display order.
function Spells.schoolsFor(classId)
	local list = {}
	for _, schoolId in ipairs(Spells.schoolOrder) do
		local school = Spells.schools[schoolId]
		for _, id in ipairs(school.classIds) do
			if id == classId then
				table.insert(list, school)
				break
			end
		end
	end
	return list
end

-- Every implemented spell a player of `classId` at `level` knows, sorted by
-- hotbarPriority (i.e. already in recommended-loadout order).
function Spells.knownFor(classId, level)
	local known = {}
	local seen = {}
	for _, school in ipairs(Spells.schoolsFor(classId)) do
		for _, grant in ipairs(school.spells) do
			local spellId, unlockLevel = grant[1], grant[2]
			local def = Spells.defs[spellId]
			if def and def.implemented ~= false and level >= unlockLevel and not seen[spellId] then
				seen[spellId] = true
				table.insert(known, spellId)
			end
		end
	end
	table.sort(known, function(a, b)
		local pa = Spells.defs[a].hotbarPriority or 99
		local pb = Spells.defs[b].hotbarPriority or 99
		if pa ~= pb then
			return pa < pb
		end
		return a < b
	end)
	return known
end

-- The class level at which `classId` unlocks `spellId`, or nil if it never does.
function Spells.unlockLevelFor(classId, spellId)
	for _, school in ipairs(Spells.schoolsFor(classId)) do
		for _, grant in ipairs(school.spells) do
			if grant[1] == spellId then
				return grant[2]
			end
		end
	end
	return nil
end

local function thresholdValue(thresholds, level)
	local value = 0
	for _, entry in ipairs(thresholds) do
		if level >= entry[1] then
			value = entry[2]
		end
	end
	return value
end

-- Aggregated school passives for a class at a level. While "all schools" test
-- mode is on, same-stat passives take the BEST value, not the sum (so a mage
-- with Pyromancer+Arcanist+Invoker doesn't triple-dip on +% magic damage).
-- Returns { magic = frac, physical = frac, melee = frac, armor = flat }.
function Spells.passivesFor(classId, level)
	local out = { magic = 0, physical = 0, melee = 0, armor = 0 }
	for _, school in ipairs(Spells.schoolsFor(classId)) do
		local passive = school.passive
		if passive then
			local value = thresholdValue(passive.thresholds, level)
			if passive.stat == "magic" then
				out.magic = math.max(out.magic, value)
			elseif passive.stat == "physical" then
				-- Physical schools boost both bow shots and melee swings.
				out.physical = math.max(out.physical, value)
				out.melee = math.max(out.melee, value)
			elseif passive.stat == "armor" then
				out.armor = math.max(out.armor, value)
			end
		end
	end
	return out
end

-- How many familiars a summon cast produces for this class/level.
function Spells.familiarCountFor(classId, level)
	local count = 1
	for _, school in ipairs(Spells.schoolsFor(classId)) do
		if school.familiars then
			count = math.max(count, thresholdValue(school.familiars, level))
		end
	end
	return count
end

-- Human-readable label for a school passive value ("+20% magic damage").
function Spells.passiveLabel(stat, value)
	if stat == "armor" then
		return ("+%d armor"):format(value)
	end
	local kind = stat == "magic" and "magic damage" or "physical damage"
	return ("+%d%% %s"):format(math.floor(value * 100 + 0.5), kind)
end

-- The school's unlock timeline: a sorted array of
--   { level, passive?, spells = {spellId, ...}, familiars? }
-- (one entry per threshold level; used by the tracker tooltip).
function Spells.timelineFor(school)
	local byLevel = {}
	local function at(level)
		local entry = byLevel[level]
		if not entry then
			entry = { level = level, spells = {} }
			byLevel[level] = entry
		end
		return entry
	end
	if school.passive then
		for _, th in ipairs(school.passive.thresholds) do
			at(th[1]).passive = th[2]
		end
	end
	for _, grant in ipairs(school.spells) do
		table.insert(at(grant[2]).spells, grant[1])
	end
	if school.familiars then
		for _, th in ipairs(school.familiars) do
			if th[2] > 1 then
				at(th[1]).familiars = th[2]
			end
		end
	end
	local timeline = {}
	for _, entry in pairs(byLevel) do
		table.insert(timeline, entry)
	end
	table.sort(timeline, function(a, b)
		return a.level < b.level
	end)
	return timeline
end

-- ---- hotbar bind + attribute helpers ---------------------------------------------

function Spells.toBind(spellId)
	return Spells.BIND_PREFIX .. spellId
end

-- The spell id inside a hotbar bind value, or nil if it's a plain item bind.
function Spells.fromBind(value)
	if typeof(value) == "string" and value:sub(1, #Spells.BIND_PREFIX) == Spells.BIND_PREFIX then
		return value:sub(#Spells.BIND_PREFIX + 1)
	end
	return nil
end

function Spells.cdAttributeFor(spellId)
	return Spells.cdAttributePrefix .. spellId
end

return Spells
