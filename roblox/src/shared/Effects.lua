-- Shared buff/debuff definitions. The server's EffectService applies these
-- (gameplay side) and replicates each active effect to its owner as a Player
-- attribute `Effect_<id>` holding the expiry time on the server clock
-- (Workspace:GetServerTimeNow()), so the client can render icons + countdowns
-- with no remotes. Effects are live-only (not persisted), like mana.

local Effects = {}

Effects.attributePrefix = "Effect_"

-- Gameplay fields an effect may carry (EffectService aggregates them across
-- everything active — multipliers multiply together):
--   walkSpeedMult    — movement speed multiplier
--   damageMults      — { melee?, physical?, magic? } outgoing damage multipliers
--   damageTakenMult  — incoming damage multiplier (< 1 = tankier)
Effects.defs = {
	slow = {
		id = "slow",
		name = "Slowed",
		kind = "debuff",
		duration = 4, -- seconds; reapplying refreshes the timer
		walkSpeedMult = 0.5,
		color = Color3.fromRGB(80, 200, 120), -- slime green: reads as its source
	},

	-- ---- innate ability buffs (see Spells.innates) ---------------------------
	defensive_stance = {
		id = "defensive_stance",
		name = "Defensive Stance",
		kind = "buff",
		duration = 6,
		damageTakenMult = 0.6,
		damageMults = { melee = 0.7, physical = 0.7, magic = 0.7 },
		color = Color3.fromRGB(150, 160, 190),
	},
	overcharge = {
		id = "overcharge",
		name = "Overcharge",
		kind = "buff",
		duration = 8,
		damageMults = { magic = 1.25 },
		color = Color3.fromRGB(150, 130, 220),
	},
	swift_step = {
		id = "swift_step",
		name = "Swift Step",
		kind = "buff",
		duration = 2,
		walkSpeedMult = 1.2,
		color = Color3.fromRGB(90, 210, 230),
	},
	minor_blessing = {
		id = "minor_blessing",
		name = "Minor Blessing",
		kind = "buff",
		duration = 5,
		damageTakenMult = 0.85,
		color = Color3.fromRGB(255, 235, 170),
	},

	-- ---- spell buffs (see shared/Spells.lua) --------------------------------
	battle_cry = {
		id = "battle_cry",
		name = "Battle Cry",
		kind = "buff",
		duration = 10,
		damageMults = { melee = 1.25, physical = 1.25 },
		color = Color3.fromRGB(220, 80, 60),
	},
	frenzy = {
		id = "frenzy",
		name = "Frenzy",
		kind = "buff",
		duration = 8,
		damageMults = { melee = 1.5, physical = 1.35 },
		walkSpeedMult = 1.2,
		color = Color3.fromRGB(170, 30, 30),
	},
	on_guard = {
		id = "on_guard",
		name = "On Guard",
		kind = "buff",
		duration = 6,
		damageTakenMult = 0.85,
		color = Color3.fromRGB(120, 150, 200),
	},
	steel_loyalty = {
		id = "steel_loyalty",
		name = "Steel Loyalty",
		kind = "buff",
		duration = 10,
		damageTakenMult = 0.7,
		color = Color3.fromRGB(150, 170, 210),
	},
	bulwark = {
		id = "bulwark",
		name = "Bulwark",
		kind = "buff",
		duration = 6,
		damageTakenMult = 0.5,
		color = Color3.fromRGB(90, 120, 190),
	},
	sprint = {
		id = "sprint",
		name = "Sprint",
		kind = "buff",
		duration = 6,
		walkSpeedMult = 1.35,
		color = Color3.fromRGB(90, 210, 230),
	},
}

function Effects.get(effectId)
	return Effects.defs[effectId]
end

-- The attribute name an active effect replicates under.
function Effects.attributeFor(effectId)
	return Effects.attributePrefix .. effectId
end

-- Reverse of attributeFor: effect id from an attribute name, or nil.
function Effects.idFromAttribute(attributeName)
	if attributeName:sub(1, #Effects.attributePrefix) == Effects.attributePrefix then
		return attributeName:sub(#Effects.attributePrefix + 1)
	end
	return nil
end

return Effects
