-- Live buffs/debuffs (not persisted, like mana). Applies the gameplay side
-- (currently walkspeed multipliers) and replicates each active effect to its
-- owner as a Player attribute `Effect_<id>` holding the expiry time on the
-- server clock — the client's effects panel renders icons/countdowns from
-- those attributes with no remotes (see shared/Effects.lua).
--
-- First real effect: slimes inflict `slow` on melee hit.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Effects = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Effects"))
local EnemyService = require(script.Parent.EnemyService)
local ClassService = require(script.Parent.ClassService)

local EffectService = {}

local BASE_WALKSPEED = 16
local EXPIRE_TICK = 0.25 -- seconds between expiry sweeps

-- [userId] = { [effectId] = expiresAt (server clock) }
local active = {}

local function walkSpeedMult(userId)
	local effects = active[userId]
	local mult = 1
	if effects then
		for effectId in pairs(effects) do
			local def = Effects.get(effectId)
			if def and def.walkSpeedMult then
				mult *= def.walkSpeedMult
			end
		end
	end
	return mult
end

local function applyWalkSpeed(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		-- Effects multiply on top of the class's own walkspeed, not raw 16.
		local classBase = BASE_WALKSPEED * ClassService.getDef(player).walkSpeedMult
		humanoid.WalkSpeed = classBase * walkSpeedMult(player.UserId)
	end
end

-- Outgoing damage multiplier from active effects for a damage kind
-- ("melee" | "physical" | "magic"). Combat reads this through the
-- EnemyService damage-mult hook registered in start().
function EffectService.damageMult(player, kind)
	local effects = active[player.UserId]
	local mult = 1
	if effects then
		for effectId in pairs(effects) do
			local def = Effects.get(effectId)
			local mults = def and def.damageMults
			if mults and mults[kind] then
				mult *= mults[kind]
			end
		end
	end
	return mult
end

-- Incoming damage multiplier from active effects (< 1 = tankier).
function EffectService.damageTakenMult(player)
	local effects = active[player.UserId]
	local mult = 1
	if effects then
		for effectId in pairs(effects) do
			local def = Effects.get(effectId)
			if def and def.damageTakenMult then
				mult *= def.damageTakenMult
			end
		end
	end
	return mult
end

-- Diminishing returns on debuffs: reapplying the same debuff within the
-- reset window shortens each new application (100% → 50% → 25% floor), so
-- chain-CC (e.g. a slime pack) can't perma-lock a player. Buffs never
-- diminish — they're the player's own casts.
local DIMINISH_STEP = 0.5
local DIMINISH_FLOOR = 0.25
local DIMINISH_RESET = 8 -- seconds without a reapplication before it resets

local diminish = {} -- [userId] = { [effectId] = { mult, lastApplied } }

local function diminishedDuration(player, def)
	if def.kind ~= "debuff" then
		return def.duration
	end
	local userDim = diminish[player.UserId]
	if not userDim then
		userDim = {}
		diminish[player.UserId] = userDim
	end
	local now = os.clock()
	local entry = userDim[def.id]
	if entry and now - entry.lastApplied <= DIMINISH_RESET then
		entry.mult = math.max(DIMINISH_FLOOR, entry.mult * DIMINISH_STEP)
	else
		entry = { mult = 1 }
		userDim[def.id] = entry
	end
	entry.lastApplied = now
	return def.duration * entry.mult
end

-- Applies (or refreshes) an effect on the player.
function EffectService.apply(player, effectId)
	local def = Effects.get(effectId)
	if not def then
		warn("[EffectService] unknown effect: " .. tostring(effectId))
		return
	end
	local effects = active[player.UserId]
	if not effects then
		effects = {}
		active[player.UserId] = effects
	end
	local expiresAt = Workspace:GetServerTimeNow() + diminishedDuration(player, def)
	-- A diminished reapplication must never CUT SHORT a longer active timer.
	if effects[effectId] and effects[effectId] > expiresAt then
		return
	end
	effects[effectId] = expiresAt
	player:SetAttribute(Effects.attributeFor(effectId), expiresAt)
	applyWalkSpeed(player)
end

local function sweepExpired()
	local now = Workspace:GetServerTimeNow()
	for userId, effects in pairs(active) do
		local player = Players:GetPlayerByUserId(userId)
		if not player then
			active[userId] = nil
			continue
		end
		local changed = false
		for effectId, expiresAt in pairs(effects) do
			if now >= expiresAt then
				effects[effectId] = nil
				player:SetAttribute(Effects.attributeFor(effectId), nil)
				changed = true
			end
		end
		if changed then
			applyWalkSpeed(player)
		end
	end
end

function EffectService.start()
	-- Slimes inflict the slowness debuff on melee hit.
	EnemyService.onPlayerHit(function(lootSource, player)
		if lootSource == "slime" then
			EffectService.apply(player, "slow")
		end
	end)

	-- Feed effect buffs/debuffs into the combat damage pipeline.
	EnemyService.registerDamageMult(function(player, kind)
		return EffectService.damageMult(player, kind)
	end)
	EnemyService.registerDamageTakenMult(function(player)
		return EffectService.damageTakenMult(player)
	end)

	-- Respawning resets WalkSpeed; reapply active effects to the new character.
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			local humanoid = character:WaitForChild("Humanoid", 5)
			if humanoid then
				applyWalkSpeed(player)
			end
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		active[player.UserId] = nil
		diminish[player.UserId] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(EXPIRE_TICK)
			sweepExpired()
		end
	end)
end

return EffectService
