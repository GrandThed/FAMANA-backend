-- Class passives (see shared/ClassPassives.lua): ONE fixed trait per main
-- class, scaling purely with the player's OWN class level — no equipment
-- involved at all. Feeds into the exact same stat hooks SynergyService
-- (equipment traits) uses, so the two stack additively without either
-- system knowing the other exists:
--   * Knight "Oakskin"            → EnemyService damage-taken hook
--   * Archer "Hawk Eye"           → EnemyService crit-chance hook
--   * Mage "Arcane Mastery"      → EffectService buff-duration hook
--   * Cleric "Vital Aura"         → HealthService always-on bonus regen
-- Recomputes on level-up and on class switch (both change which tier is
-- active). Replicates the active tier as the `ClassPassive` attribute (JSON:
-- { id, name, level, nextLevel? }) so client UI can show it with no remote.

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClassPassives = require(Shared:WaitForChild("ClassPassives"))

local EnemyService = require(script.Parent.EnemyService)
local EffectService = require(script.Parent.EffectService)
local HealthService = require(script.Parent.HealthService)
local ClassService = require(script.Parent.ClassService)
local GatheringService = require(script.Parent.GatheringService)
local DropService = require(script.Parent.DropService)
local CraftingService = require(script.Parent.CraftingService)

local ClassPassiveService = {}

local EMPTY = {}

-- [userId] = active stat block for the player's current class+level (see
-- ClassPassives.statsFor) — e.g. { damageTakenMult = 0.91 } for a lvl 7 Knight.
local statsCache = {}

local function statsFor(player)
	return statsCache[player.UserId] or EMPTY
end

function ClassPassiveService.getStats(player)
	return statsFor(player)
end

local function recompute(player)
	local classDef = ClassService.getDef(player)
	local level = ClassService.getLevel(player)
	if not classDef then
		return
	end

	local stats = ClassPassives.activeStats(classDef.id, level) or EMPTY
	statsCache[player.UserId] = stats

	local def = ClassPassives.get(classDef.id)
	if def then
		player:SetAttribute(
			"ClassPassive",
			HttpService:JSONEncode({
				id = def.id,
				name = def.name,
				icon = def.icon,
				level = level,
				nextLevel = ClassPassives.nextThreshold(classDef.id, level),
			})
		)
	end

	-- Brawler-style always-on regen depends on max HP; re-derive it now.
	HealthService.refreshMaxHealth(player)
end

function ClassPassiveService.start()
	-- ---- stat hooks ------------------------------------------------------
	EnemyService.registerDamageTakenMult(function(player)
		return statsFor(player).damageTakenMult or 1
	end)
	EnemyService.registerCritChanceBonus(function(player)
		return statsFor(player).crit or 0
	end)
	EffectService.registerDurationMult(function(player)
		return 1 + (statsFor(player).duration or 0)
	end)
	HealthService.registerBonusRegen(function(player)
		local fraction = statsFor(player).regen or 0
		if fraction <= 0 then
			return 0
		end
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		return humanoid and fraction * humanoid.MaxHealth or 0
	end)

	-- ---- gathering identities (docs/TRAITS_V2.md §5) -----------------------
	-- Knight harvests natural resources better; Cleric owns herbs (waits on
	-- herb nodes + the sickle toolType); Archer loots more from enemies
	-- (never equipment); Mage brews doubles (waits on potion recipes).
	GatheringService.registerYieldBonus(function(player, toolType)
		local stats = statsFor(player)
		if toolType == "sickle" then
			return stats.herbYield or 0
		end
		return stats.gatherYield or 0
	end)
	DropService.registerQuantityBonus(function(player)
		return statsFor(player).mobDrops or 0
	end)
	CraftingService.registerDoubleCraftChance(function(player, recipeDef)
		if recipeDef.potion then
			return statsFor(player).craftDouble or 0
		end
		return 0
	end)

	-- ---- recompute triggers ------------------------------------------------
	-- Level and Class attributes both move which tier is active (Level
	-- directly; Class swaps which passive applies at the new level).
	Players.PlayerAdded:Connect(function(player)
		player:GetAttributeChangedSignal("Level"):Connect(function()
			recompute(player)
		end)
		player:GetAttributeChangedSignal("Class"):Connect(function()
			recompute(player)
		end)
		player.CharacterAdded:Connect(function()
			recompute(player)
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		statsCache[player.UserId] = nil
	end)
end

return ClassPassiveService
