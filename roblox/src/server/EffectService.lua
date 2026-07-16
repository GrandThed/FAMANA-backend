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

-- registerDurationMult: fn(player, def) -> multiplier on BUFF durations
-- (Perseverance trait). Debuffs are never extended by it.
local durationMultHooks = {}
function EffectService.registerDurationMult(fn)
	table.insert(durationMultHooks, fn)
end

local function hookedDurationMult(player, def)
	local mult = 1
	for _, fn in ipairs(durationMultHooks) do
		local ok, value = pcall(fn, player, def)
		if ok and typeof(value) == "number" then
			mult *= value
		end
	end
	return mult
end

-- Final applied duration: buffs get the duration-mult hooks (Perseverance),
-- debuffs get diminishing returns instead.
local function effectDuration(player, def)
	if def.kind ~= "debuff" then
		return def.duration * hookedDurationMult(player, def)
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

-- Applies (or refreshes) an effect on the player. Returns the duration it
-- landed with (post duration-mult hooks) so casters that mirror the window
-- in their own state (Prophecy's undying, Legion's empower) stay in sync
-- with the HUD; nil if a longer active timer won.
function EffectService.apply(player, effectId)
	local def = Effects.get(effectId)
	if not def then
		warn("[EffectService] unknown effect: " .. tostring(effectId))
		return nil
	end
	local effects = active[player.UserId]
	if not effects then
		effects = {}
		active[player.UserId] = effects
	end
	local duration = effectDuration(player, def)
	local expiresAt = Workspace:GetServerTimeNow() + duration
	-- A diminished reapplication must never CUT SHORT a longer active timer.
	if effects[effectId] and effects[effectId] > expiresAt then
		return nil
	end
	effects[effectId] = expiresAt
	player:SetAttribute(Effects.attributeFor(effectId), expiresAt)
	applyWalkSpeed(player)
	return duration
end

-- Whether an effect is currently running on the player (Bloodbath's kill
-- window, Crusade's lifesteal — checked from hooks, not stored twice).
function EffectService.isActive(player, effectId)
	local effects = active[player.UserId]
	local expiresAt = effects and effects[effectId]
	return expiresAt ~= nil and Workspace:GetServerTimeNow() < expiresAt
end

-- Adds seconds onto an ACTIVE effect's timer (Bloodbath stretching Frenzy);
-- no-op if it isn't running.
function EffectService.extend(player, effectId, seconds)
	local effects = active[player.UserId]
	local expiresAt = effects and effects[effectId]
	if not expiresAt or Workspace:GetServerTimeNow() >= expiresAt then
		return
	end
	effects[effectId] = expiresAt + seconds
	player:SetAttribute(Effects.attributeFor(effectId), expiresAt + seconds)
end

-- Strips every active DEBUFF (Miracle's cleanse). Buffs are untouched.
function EffectService.cleanse(player)
	local effects = active[player.UserId]
	if not effects then
		return
	end
	local changed = false
	for effectId in pairs(effects) do
		local def = Effects.get(effectId)
		if def and def.kind == "debuff" then
			effects[effectId] = nil
			player:SetAttribute(Effects.attributeFor(effectId), nil)
			changed = true
		end
	end
	if changed then
		applyWalkSpeed(player)
	end
end

-- Removes an active effect ahead of its expiry — consumed "next X" primes
-- (Double Nock, Overflow) clear their HUD marker the moment they're spent.
-- Safe no-op if the effect isn't active.
function EffectService.clear(player, effectId)
	local effects = active[player.UserId]
	if effects and effects[effectId] then
		effects[effectId] = nil
		player:SetAttribute(Effects.attributeFor(effectId), nil)
		applyWalkSpeed(player)
	end
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
	local function watchPlayer(player)
		player.CharacterAdded:Connect(function(character)
			local humanoid = character:WaitForChild("Humanoid", 5)
			if humanoid then
				applyWalkSpeed(player)
			end
		end)
	end

	Players.PlayerAdded:Connect(watchPlayer)
	-- Players who connected during server boot fired PlayerAdded before the
	-- connect above (same sweep as PlayerService).
	for _, player in ipairs(Players:GetPlayers()) do
		watchPlayer(player)
	end

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
