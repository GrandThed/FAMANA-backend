-- Trait (synergy) definitions — Phase A of the TFT-style equipment system
-- (see docs/TRAITS_AND_SPELLS.md + docs/TRAITS.md). Equipment carries fixed
-- `traits` (points per trait) and an `itemLevel` on its def; the points of
-- every NON-INERT equipped piece sum per trait, and the highest threshold
-- the total reaches grants that tier's stats. An item is inert while its
-- itemLevel is above the player's ACTIVE class level (red square in the UI,
-- contributes nothing) — nothing is ever auto-unequipped.
--
-- Ladders follow the rebalanced standard grid (docs/TRAITS_CATALOG.md):
-- thresholds at 2/5/8/12/16/20/25/30, values from v(p) = V_max*(p/p_max)^1.5
-- so value-per-point GROWS with depth (concentration beats splashing), with
-- per-trait depth caps where a stat stays safe. Deferred traits (Guardian,
-- Roll/Dash movement actives, mana regen, gathering) join the catalog when
-- their systems exist.

local Items = require(script.Parent.Items)
local Spells = require(script.Parent.Spells) -- school ids also earn equipment points
local Rarity = require(script.Parent.Rarity) -- shapes rolled drops (bonus points + line count)

local Traits = {}

-- thresholds: { {points, stats} } — the highest reached entry applies.
-- Stat keys (aggregated additively across traits by statsFor):
--   crit           — added critical strike chance (fraction)
--   attackSpeed    — swing rate bonus (fraction; cooldown = base / (1 + it))
--   physicalDamage — bonus on physical/melee outgoing damage (fraction)
--   magicDamage    — bonus on magic outgoing damage (fraction)
--   critDamage     — added to the crit multiplier (0.40 → crits hit x2.4)
--   lifesteal      — fraction of WEAPON damage returned as healing
--   duration       — buff/ability duration bonus (fraction)
--   debuffDuration — bonus on debuff durations YOU inflict (stuns/slows)
--   hp             — max HP bonus (fraction)
--   regen          — HP regen per second, as a fraction of max HP (always on)
--   armor          — flat armor; damage taken × 100/(100+armor)
--   dodge          — chance to fully evade an enemy hit (fraction)
--   healReceived   — bonus on healing received (potions/ally spells; NOT regen)
--   reflect        — fraction of melee damage taken reflected at the attacker
--   manaRegen      — mana regen bonus (fraction)
Traits.defs = {
	lynx_eye = {
		id = "lynx_eye",
		name = "Lynx Eye",
		icon = "👁️",
		color = Color3.fromRGB(240, 190, 70),
		description = "Sharpened senses raise your critical strike chance.",
		-- Depth 30: past 100% total crit the overflow becomes SUPER CRIT
		-- chance (x3 hits) once EnemyService implements the overflow roll —
		-- see TRAITS_CATALOG §5.7. Unreachable until deep prestige stacking.
		thresholds = {
			{ 2, { crit = 0.02 } },
			{ 5, { crit = 0.08 } },
			{ 8, { crit = 0.15 } },
			{ 12, { crit = 0.28 } },
			{ 16, { crit = 0.43 } },
			{ 20, { crit = 0.61 } },
			{ 25, { crit = 0.85 } },
			{ 30, { crit = 1.10 } },
		},
	},
	agile_hands = {
		id = "agile_hands",
		name = "Agile Hands",
		icon = "⚡",
		color = Color3.fromRGB(120, 210, 240),
		description = "Faster swings with every weapon and tool.",
		thresholds = {
			{ 2, { attackSpeed = 0.02 } },
			{ 5, { attackSpeed = 0.08 } },
			{ 8, { attackSpeed = 0.16 } },
			{ 12, { attackSpeed = 0.30 } },
			{ 16, { attackSpeed = 0.47 } },
			{ 20, { attackSpeed = 0.65 } },
			{ 25, { attackSpeed = 0.91 } },
			{ 30, { attackSpeed = 1.20 } },
		},
	},
	perseverance = {
		id = "perseverance",
		name = "Perseverance",
		icon = "⏳",
		color = Color3.fromRGB(200, 160, 220),
		description = "Your buffs and abilities last longer.",
		-- Depth 16: duration is cooldown-bounded, so it stops early.
		thresholds = {
			{ 2, { duration = 0.02 } },
			{ 5, { duration = 0.07 } },
			{ 8, { duration = 0.14 } },
			{ 12, { duration = 0.26 } },
			{ 16, { duration = 0.40 } },
		},
	},
	brawler = {
		id = "brawler",
		name = "Brawler",
		icon = "💪",
		color = Color3.fromRGB(220, 110, 90),
		description = "More max HP, and your health trickles back even in combat.",
		thresholds = {
			{ 2, { hp = 0.02, regen = 0.005 } },
			{ 5, { hp = 0.09, regen = 0.01 } },
			{ 8, { hp = 0.18, regen = 0.015 } },
			{ 12, { hp = 0.33, regen = 0.025 } },
			{ 16, { hp = 0.50, regen = 0.035 } },
			{ 20, { hp = 0.71, regen = 0.05 } },
			{ 25, { hp = 0.99, regen = 0.065 } },
			{ 30, { hp = 1.30, regen = 0.08 } },
		},
	},
	bastion = {
		id = "bastion",
		name = "Bastion",
		icon = "🧱",
		color = Color3.fromRGB(150, 160, 190),
		description = "Armor that shrugs off physical and magical punishment alike.",
		thresholds = {
			{ 2, { armor = 3 } },
			{ 5, { armor = 12 } },
			{ 8, { armor = 25 } },
			{ 12, { armor = 45 } },
			{ 16, { armor = 70 } },
			{ 20, { armor = 98 } },
			{ 25, { armor = 137 } },
			{ 30, { armor = 180 } },
		},
	},
	evasion = {
		id = "evasion",
		name = "Evasion",
		icon = "🍃",
		color = Color3.fromRGB(130, 210, 140),
		description = "A chance to fully evade enemy hits.",
		-- Depth 25: dodge hard-caps low — high evasion is frustration
		-- mechanics, so the ladder ends at 25%.
		thresholds = {
			{ 5, { dodge = 0.02 } },
			{ 8, { dodge = 0.04 } },
			{ 12, { dodge = 0.08 } },
			{ 16, { dodge = 0.13 } },
			{ 20, { dodge = 0.18 } },
			{ 25, { dodge = 0.25 } },
		},
	},
	physical_training = {
		id = "physical_training",
		name = "Physical Training",
		icon = "⚔️",
		color = Color3.fromRGB(210, 130, 80),
		description = "Raw conditioning: your physical damage hits harder.",
		thresholds = {
			{ 2, { physicalDamage = 0.02 } },
			{ 5, { physicalDamage = 0.09 } },
			{ 8, { physicalDamage = 0.18 } },
			{ 12, { physicalDamage = 0.34 } },
			{ 16, { physicalDamage = 0.52 } },
			{ 20, { physicalDamage = 0.73 } },
			{ 25, { physicalDamage = 1.02 } },
			{ 30, { physicalDamage = 1.35 } },
		},
	},
	arcane_practice = {
		id = "arcane_practice",
		name = "Arcane Practice",
		icon = "🌠",
		color = Color3.fromRGB(140, 110, 230),
		description = "Disciplined study: your magic damage hits harder.",
		thresholds = {
			{ 2, { magicDamage = 0.02 } },
			{ 5, { magicDamage = 0.09 } },
			{ 8, { magicDamage = 0.18 } },
			{ 12, { magicDamage = 0.34 } },
			{ 16, { magicDamage = 0.52 } },
			{ 20, { magicDamage = 0.73 } },
			{ 25, { magicDamage = 1.02 } },
			{ 30, { magicDamage = 1.35 } },
		},
	},
	executioner = {
		id = "executioner",
		name = "Executioner",
		icon = "🪓",
		color = Color3.fromRGB(180, 60, 60),
		description = "Your critical strikes hit far beyond their base double damage.",
		thresholds = {
			{ 2, { critDamage = 0.03 } },
			{ 5, { critDamage = 0.11 } },
			{ 8, { critDamage = 0.22 } },
			{ 12, { critDamage = 0.40 } },
			{ 16, { critDamage = 0.61 } },
			{ 20, { critDamage = 0.86 } },
			{ 25, { critDamage = 1.20 } },
		},
	},
	leech = {
		id = "leech",
		name = "Leech",
		icon = "🩸",
		color = Color3.fromRGB(170, 30, 60),
		description = "Weapon hits return a share of their damage as healing.",
		thresholds = {
			{ 2, { lifesteal = 0.01 } },
			{ 5, { lifesteal = 0.03 } },
			{ 8, { lifesteal = 0.05 } },
			{ 12, { lifesteal = 0.10 } },
			{ 16, { lifesteal = 0.15 } },
			{ 20, { lifesteal = 0.21 } },
			{ 25, { lifesteal = 0.30 } },
		},
	},
	inferno = {
		id = "inferno",
		name = "Inferno",
		icon = "♨️",
		color = Color3.fromRGB(230, 120, 40),
		description = "The stuns and slows you inflict last longer.",
		-- Depth 16, and enemy-side diminishing returns exist SO this can:
		-- reapplied CC within 8s lands at 100/50/25% duration.
		thresholds = {
			{ 2, { debuffDuration = 0.02 } },
			{ 5, { debuffDuration = 0.09 } },
			{ 8, { debuffDuration = 0.18 } },
			{ 12, { debuffDuration = 0.32 } },
			{ 16, { debuffDuration = 0.50 } },
		},
	},
	life_essence = {
		id = "life_essence",
		name = "Life Essence",
		icon = "💗",
		color = Color3.fromRGB(240, 150, 170),
		description = "Healing you receive is amplified (regen unaffected).",
		thresholds = {
			{ 2, { healReceived = 0.02 } },
			{ 5, { healReceived = 0.10 } },
			{ 8, { healReceived = 0.19 } },
			{ 12, { healReceived = 0.36 } },
			{ 16, { healReceived = 0.55 } },
		},
	},
	retribution = {
		id = "retribution",
		name = "Retribution",
		icon = "🌵",
		color = Color3.fromRGB(120, 160, 90),
		description = "Melee attackers take a share of the damage they deal you.",
		thresholds = {
			{ 2, { reflect = 0.02 } },
			{ 5, { reflect = 0.10 } },
			{ 8, { reflect = 0.19 } },
			{ 12, { reflect = 0.36 } },
			{ 16, { reflect = 0.55 } },
		},
	},
	clarity = {
		id = "clarity",
		name = "Clarity",
		icon = "💧",
		color = Color3.fromRGB(90, 160, 230),
		description = "A calm mind: your mana returns faster.",
		thresholds = {
			{ 2, { manaRegen = 0.05 } },
			{ 5, { manaRegen = 0.19 } },
			{ 8, { manaRegen = 0.39 } },
			{ 12, { manaRegen = 0.71 } },
			{ 16, { manaRegen = 1.10 } },
		},
	},
	-- Gathering traits: pickaxe/axe MAIN lines only (see Traits.roll), and
	-- per the hand rule they only work while the tool is out. They AMPLIFY
	-- the class gathering identities (shared/ClassPassives) additively.
	prospector = {
		id = "prospector",
		name = "Prospector",
		icon = "⛏️",
		color = Color3.fromRGB(170, 140, 100),
		description = "Better mining: more stone and ore per swing.",
		thresholds = {
			{ 2, { miningYield = 0.04 } },
			{ 5, { miningYield = 0.17 } },
			{ 8, { miningYield = 0.35, miningDouble = 0.10 } },
			{ 12, { miningYield = 0.65, miningDouble = 0.10 } },
			{ 16, { miningYield = 1.00, miningDouble = 0.10, miningNoDeplete = 0.25 } },
		},
	},
	woodsman = {
		id = "woodsman",
		name = "Woodsman",
		icon = "🪵",
		color = Color3.fromRGB(140, 110, 70),
		description = "Better logging: more wood per swing.",
		thresholds = {
			{ 2, { loggingYield = 0.04 } },
			{ 5, { loggingYield = 0.17 } },
			{ 8, { loggingYield = 0.35, loggingDouble = 0.10 } },
			{ 12, { loggingYield = 0.65, loggingDouble = 0.10 } },
			{ 16, { loggingYield = 1.00, loggingDouble = 0.10, loggingNoDeplete = 0.25 } },
		},
	},
}

-- Display order (offense → defense → utility).
Traits.order = {
	"lynx_eye",
	"agile_hands",
	"physical_training",
	"arcane_practice",
	"executioner",
	"leech",
	"perseverance",
	"inferno",
	"brawler",
	"bastion",
	"evasion",
	"life_essence",
	"retribution",
	"clarity",
	"prospector",
	"woodsman",
}

function Traits.get(traitId)
	return Traits.defs[traitId]
end

-- ---- thresholds ----------------------------------------------------------------

-- Stats of the highest threshold `points` reaches, or nil below the first.
function Traits.activeStats(traitId, points)
	local def = Traits.defs[traitId]
	if not def then
		return nil
	end
	local stats
	for _, threshold in ipairs(def.thresholds) do
		if points >= threshold[1] then
			stats = threshold[2]
		end
	end
	return stats
end

-- The next threshold above `points`, or nil once maxed.
function Traits.nextThreshold(traitId, points)
	local def = Traits.defs[traitId]
	if not def then
		return nil
	end
	for _, threshold in ipairs(def.thresholds) do
		if threshold[1] > points then
			return threshold[1]
		end
	end
	return nil
end

-- ---- aggregation ----------------------------------------------------------------

-- The effective (itemLevel, traits) of an inventory entry: rolled instance
-- meta ({ itemLevel, rarity?, traits }) overrides the def's fixed values.
-- (Rarity has its own accessor: Rarity.forEntry.)
function Traits.entryInfo(entry, def)
	local meta = entry and entry.meta
	if typeof(meta) == "table" then
		return meta.itemLevel or (def and def.itemLevel) or 0, meta.traits or (def and def.traits)
	end
	return (def and def.itemLevel) or 0, def and def.traits
end

-- Whether an equipped entry is inert (contributes nothing) at a player level.
function Traits.isInert(entry, def, level)
	local itemLevel = Traits.entryInfo(entry, def)
	return itemLevel > level
end

-- Sums trait AND school points across the equipped (paper doll) items of an
-- inventory listing, skipping inert pieces. Schools (Berserker, Pyromancer…)
-- are equipment-earned exactly like traits — SynergyService splits the two
-- families out of this one map. Returns { [traitOrSchoolId] = points }.
--
-- HAND RULE (docs/TRAITS_V2.md §1.4): armor/rings always count, but the
-- paper doll's weapon/offhand slots (x = 0/1) count only while nothing
-- ELSE is wielded — pull a grid tool out (`heldItemId`) and the doll's
-- hand slots switch off while the held tool's traits switch on (first
-- matching grid entry; still inert-gated by its item level).
local WEAPON_SLOT_X, OFFHAND_SLOT_X = 0, 1

local function addEntryTraits(totals, entry, level)
	local def = Items.get(entry.itemId)
	local itemLevel, itemTraits = Traits.entryInfo(entry, def)
	if typeof(itemTraits) == "table" and itemLevel <= level then
		for traitId, points in pairs(itemTraits) do
			if (Traits.defs[traitId] or Spells.schools[traitId]) and typeof(points) == "number" then
				totals[traitId] = (totals[traitId] or 0) + points
			end
		end
	end
end

function Traits.totalsFor(inventory, level, heldItemId)
	-- Is the held item one of the doll's own hand slots? Then the doll is
	-- the wielded loadout and counts as-is (the default combat stance —
	-- also the nothing-held case, so traits don't flicker on unequip).
	local handSlotsActive = true
	if heldItemId then
		local heldIsDollHand = false
		for _, entry in ipairs(inventory) do
			if
				entry.containerId == "equipment"
				and (entry.x == WEAPON_SLOT_X or entry.x == OFFHAND_SLOT_X)
				and entry.itemId == heldItemId
			then
				heldIsDollHand = true
				break
			end
		end
		handSlotsActive = heldIsDollHand
	end

	local totals = {}
	for _, entry in ipairs(inventory) do
		if entry.containerId == "equipment" then
			local isHandSlot = entry.x == WEAPON_SLOT_X or entry.x == OFFHAND_SLOT_X
			if handSlotsActive or not isHandSlot then
				addEntryTraits(totals, entry, level)
			end
		end
	end

	-- A wielded GRID item (hotbar-bound tool/weapon) contributes instead of
	-- the stowed doll hands. First matching entry wins — with multiple
	-- copies (e.g. rolled instances) the backend's stable order decides.
	if heldItemId and not handSlotsActive then
		for _, entry in ipairs(inventory) do
			if entry.containerId ~= "equipment" and entry.itemId == heldItemId then
				addEntryTraits(totals, entry, level)
				break
			end
		end
	end
	return totals
end

-- ---- rolling (server-side drops) ---------------------------------------------------

-- Which traits an item type can roll (weapons offensive, armor defensive,
-- rings anything). Types not listed (tools, resources...) never roll.
local TYPE_POOLS = {
	weapon = {
		"lynx_eye",
		"agile_hands",
		"perseverance",
		"physical_training",
		"arcane_practice",
		"inferno",
		"executioner",
		"leech",
	},
	armor = { "brawler", "bastion", "evasion", "life_essence", "retribution" },
	ring = Traits.order,
}

-- Tools roll their OWN gathering trait as the main line (a pickaxe with
-- Woodsman is nonsense and can't roll); side lines come from a small
-- "handling" pool and never schools. Hand rule applies: tool traits only
-- work while the tool is out.
local TOOL_MAINS = {
	pickaxe = "prospector",
	axe = "woodsman",
}
local HANDLING_POOL = { "agile_hands", "evasion" }

-- Chance for a rolled line to be a SCHOOL (Berserker, Pyromancer…) instead
-- of a stat trait — the equipment-only path to spells and school passives.
local SCHOOL_ROLL_CHANCE = 0.25

local function rollLineId(pool, allowSchools)
	if allowSchools and math.random() < SCHOOL_ROLL_CHANCE then
		return Spells.schoolOrder[math.random(#Spells.schoolOrder)]
	end
	return pool[math.random(#pool)]
end

-- Rolls instance meta for a drop under the "rarity = concentration + bonus"
-- rules (docs/TRAITS_V2.md §6). A weighted RARITY (shared/Rarity) sets both
-- axes of the roll:
--   * concentration — the MAIN line carries mainShare × itemLevel points
--     (a legendary's main line is the FULL item level; the convex ladders
--     are what turn that concentration into power), never more.
--   * bonus — bonusPercent of the item level (ceil, min 1) arrives on top,
--     spread over SIDE lines with the leftover (itemLevel - main) points.
-- Every line keeps ≥1 point, so tiny budgets collapse to fewer lines. The
-- item's inert gate stays its plain level.
-- Returns { itemLevel, rarity, traits } or nil for un-rollable types.
function Traits.roll(def, itemLevel)
	itemLevel = math.floor(itemLevel or 0)
	if not def or itemLevel < 1 then
		return nil
	end
	local forcedMain, sidePool, allowSchools
	if def.type == "tool" then
		forcedMain = def.toolType and TOOL_MAINS[def.toolType]
		sidePool = HANDLING_POOL
		allowSchools = false
		if not forcedMain then
			return nil
		end
	else
		sidePool = TYPE_POOLS[def.type]
		allowSchools = true
		if not sidePool then
			return nil
		end
	end

	local rarity = Rarity.roll()
	local bonus = 0
	if rarity.bonusPercent > 0 then
		bonus = math.max(1, math.ceil(itemLevel * rarity.bonusPercent))
	end
	local mainPoints = math.max(1, math.floor(itemLevel * rarity.mainShare))
	local sideBudget = itemLevel + bonus - mainPoints

	-- Total line count the tier aims for; every line needs ≥1 point.
	local lineTarget = rarity.lines
	if typeof(lineTarget) == "table" then
		lineTarget = math.random(lineTarget[1], lineTarget[2])
	end
	local sideLines = math.min(lineTarget - 1, sideBudget)

	-- Distinct line ids, main line first (forced for tools); the pool can
	-- run short of fresh ids (retries hit duplicates), in which case the
	-- roll carries fewer lines.
	local ids, seen = {}, {}
	if forcedMain then
		seen[forcedMain] = true
		ids[1] = forcedMain
	end
	local attempts = 0
	while #ids < sideLines + 1 and attempts < 20 do
		attempts += 1
		local id = rollLineId(sidePool, allowSchools)
		if not seen[id] then
			seen[id] = true
			ids[#ids + 1] = id
		end
	end

	local traits = {}
	traits[ids[1]] = mainPoints
	local sideCount = #ids - 1
	if sideCount > 0 then
		-- Every side line opens at 1 point; the rest sprinkle randomly,
		-- but a side line never out-grows the main line (mainShare is the
		-- tier's concentration cap) — saturated overflow folds into main.
		for index = 2, #ids do
			traits[ids[index]] = 1
		end
		for _ = 1, sideBudget - sideCount do
			local candidates = {}
			for index = 2, #ids do
				if traits[ids[index]] < mainPoints then
					table.insert(candidates, ids[index])
				end
			end
			if #candidates > 0 then
				local id = candidates[math.random(#candidates)]
				traits[id] += 1
			else
				traits[ids[1]] += 1
			end
		end
	elseif sideBudget > 0 then
		-- No fresh side ids (tiny pools): fold the leftovers into the main.
		traits[ids[1]] += sideBudget
	end
	return { itemLevel = itemLevel, rarity = rarity.id, traits = traits }
end

-- Collapses totals into one combined stat block (active tiers only, summed
-- additively across traits): { crit?, attackSpeed?, duration?, hp?, regen?,
-- armor?, dodge? }.
function Traits.statsFor(totals)
	local out = {}
	for traitId, points in pairs(totals) do
		local stats = Traits.activeStats(traitId, points)
		if stats then
			for key, value in pairs(stats) do
				out[key] = (out[key] or 0) + value
			end
		end
	end
	return out
end

-- ---- labels (tooltips) --------------------------------------------------------------

local STAT_ORDER = {
	"crit",
	"attackSpeed",
	"physicalDamage",
	"magicDamage",
	"critDamage",
	"lifesteal",
	"duration",
	"debuffDuration",
	"hp",
	"regen",
	"armor",
	"dodge",
	"healReceived",
	"reflect",
	"manaRegen",
	"miningYield",
	"miningDouble",
	"miningNoDeplete",
	"loggingYield",
	"loggingDouble",
	"loggingNoDeplete",
}

local function percentLabel(format)
	return function(v)
		return format:format(math.floor(v * 100 + 0.5))
	end
end

local STAT_LABELS = {
	crit = percentLabel("+%d%% crit chance"),
	attackSpeed = percentLabel("+%d%% attack speed"),
	physicalDamage = percentLabel("+%d%% physical damage"),
	magicDamage = percentLabel("+%d%% magic damage"),
	critDamage = percentLabel("+%d%% crit damage"),
	lifesteal = percentLabel("+%d%% lifesteal"),
	duration = percentLabel("+%d%% ability duration"),
	debuffDuration = percentLabel("+%d%% debuff duration"),
	hp = percentLabel("+%d%% max HP"),
	regen = percentLabel("+%d%%/s HP regen"),
	armor = function(v)
		return ("+%d armor"):format(v)
	end,
	dodge = percentLabel("+%d%% dodge"),
	healReceived = percentLabel("+%d%% healing received"),
	reflect = percentLabel("reflect %d%% melee damage"),
	manaRegen = percentLabel("+%d%% mana regen"),
	miningYield = percentLabel("+%d%% stone & ore yield"),
	miningDouble = percentLabel("%d%% double harvest"),
	miningNoDeplete = percentLabel("%d%% chance nodes don't deplete"),
	loggingYield = percentLabel("+%d%% wood yield"),
	loggingDouble = percentLabel("%d%% double harvest"),
	loggingNoDeplete = percentLabel("%d%% chance trees don't deplete"),
}

function Traits.statLabel(key, value)
	local format = STAT_LABELS[key]
	return format and format(value) or (key .. " " .. tostring(value))
end

-- One line for a tier's stat block: "+50% max HP, +4%/s HP regen".
function Traits.tierLabel(stats)
	local parts = {}
	for _, key in ipairs(STAT_ORDER) do
		if stats[key] then
			table.insert(parts, Traits.statLabel(key, stats[key]))
		end
	end
	return table.concat(parts, ", ")
end

return Traits
