-- Classes: Knight / Archer / Mage / Cleric. MVP pass is passive stats
-- only (no active abilities yet). A player can switch class at any time
-- (e.g. via the inventory panel); each class keeps its own level/xp track
-- (see PlayerService), so switching never erases progress on another class.
--
-- Ownership split to avoid systems stepping on each other:
--   * HealthService still owns MaxHealth/Health on spawn (reads
--     Classes.statsAtLevel itself to scale HP by class + level).
--   * ManaService still owns the regen tick; it just reads the
--     "ManaRegenAmount" attribute this service sets instead of a fixed
--     constant.
--   * ClassService owns WalkSpeed, Mana caps, the switch-class remote, and
--     the AD/AP/Armor/MR stat lookups combat code calls into.
--
-- Stats scale with level (see shared/Classes.lua statsAtLevel): weapons and
-- spells no longer carry their own flat damage — AD/AP alone determine
-- outgoing damage, Armor/MR alone determine incoming mitigation.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Classes = require(Shared:WaitForChild("Classes"))
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local PlayerService = require(script.Parent.PlayerService)
local HealthService = require(script.Parent.HealthService)

local ClassService = {}

local BASE_WALK_SPEED = 16 -- Roblox's default Humanoid.WalkSpeed

local switchClassRemote -- RemoteFunction, resolved in start()

local function classDefFor(player)
	local profile = PlayerService.get(player)
	return Classes.get(profile and profile.currentClass)
end

local function levelFor(player)
	local profile = PlayerService.get(player)
	return (profile and profile.level) or 1
end

-- ---- lookups used by combat/health/mana systems ---------------------------

function ClassService.getDef(player)
	return classDefFor(player)
end

function ClassService.getLevel(player)
	return levelFor(player)
end

-- All six live combat stats (hp, mana, armor, mr, ad, ap) for this player's
-- current class at their current level. See shared/Classes.lua.
function ClassService.getStats(player)
	return Classes.statsAtLevel(classDefFor(player), levelFor(player))
end

function ClassService.getAD(player)
	return ClassService.getStats(player).ad
end

function ClassService.getAP(player)
	return ClassService.getStats(player).ap
end

function ClassService.getArmor(player)
	return ClassService.getStats(player).armor
end

function ClassService.getMR(player)
	return ClassService.getStats(player).mr
end

function ClassService.getCritBonus(player)
	return classDefFor(player).critChanceBonus
end

-- ---- live stat application -------------------------------------------------

-- Replicates the combat stats that don't already have their own attribute
-- (Armor/MR/AD/AP — MaxMana/Mana are set by the caller directly, MaxHealth
-- lives on the Humanoid) so read-only UI (CharacterUI) can show them without
-- a remote, same pattern as Level/Xp/Gold/etc.
local function applyStatAttributes(player, stats)
	player:SetAttribute("Armor", stats.armor)
	player:SetAttribute("MagicResist", stats.mr)
	player:SetAttribute("AttackDamage", stats.ad)
	player:SetAttribute("AbilityPower", stats.ap)
end

-- Movement + mana caps only (called on spawn). Deliberately does NOT touch
-- Health/MaxHealth — HealthService owns restoring saved HP on spawn and
-- would otherwise race with this.
function ClassService.applyMovementAndMana(player)
	local classDef = classDefFor(player)
	local stats = Classes.statsAtLevel(classDef, levelFor(player))

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = BASE_WALK_SPEED * classDef.walkSpeedMult
	end

	player:SetAttribute("MaxMana", stats.mana)
	player:SetAttribute("Mana", stats.mana)
	player:SetAttribute("ManaRegenAmount", Config.Mana.regenAmount * classDef.manaRegenMult)
	applyStatAttributes(player, stats)
end

-- Full "respec" refresh for an explicit class switch: unlike spawn, this
-- DOES reset Health/Mana to the new class's full amounts — switching class
-- mid-session is a deliberate action, so a clean refill is the expected
-- (and simplest) behavior rather than trying to rescale a partial HP bar.
function ClassService.respecLiveStats(player)
	local classDef = classDefFor(player)
	local stats = Classes.statsAtLevel(classDef, levelFor(player))

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = BASE_WALK_SPEED * classDef.walkSpeedMult
		humanoid.MaxHealth = stats.hp
		humanoid.Health = stats.hp
	end

	player:SetAttribute("MaxMana", stats.mana)
	player:SetAttribute("Mana", stats.mana)
	player:SetAttribute("ManaRegenAmount", Config.Mana.regenAmount * classDef.manaRegenMult)
	applyStatAttributes(player, stats)
end

-- Re-derives HP/Mana caps after a level-up (called via
-- PlayerService.registerLevelUpHandler). Unlike respecLiveStats, current
-- HP/Mana stay absolute — leveling up only raises the ceiling, it doesn't
-- refill you (HealthService.refreshMaxHealth already follows this pattern
-- for HP; this mirrors it for Mana).
function ClassService.refreshStatsForLevel(player)
	local stats = ClassService.getStats(player)

	HealthService.refreshMaxHealth(player)

	local currentMana = player:GetAttribute("Mana") or stats.mana
	player:SetAttribute("MaxMana", stats.mana)
	player:SetAttribute("Mana", math.min(currentMana, stats.mana))
	applyStatAttributes(player, stats)
end

-- ---- switching --------------------------------------------------------------

-- Returns (ok, errorCode). errorCode is one of "invalid_class" | "not_loaded".
function ClassService.switchClass(player, classId)
	if not Classes.isValid(classId) then
		return false, "invalid_class"
	end
	if HealthService.isDowned(player) then
		return false, "downed"
	end

	local profile = PlayerService.get(player)
	if not profile then
		return false, "not_loaded"
	end

	if profile.currentClass == classId then
		return true
	end

	profile.classLevels[classId] = profile.classLevels[classId] or { level = 1, xp = 0 }
	local lv = profile.classLevels[classId]

	profile.currentClass = classId
	profile.level = lv.level
	profile.xp = lv.xp

	player:SetAttribute("Class", classId)
	player:SetAttribute("Level", lv.level)
	player:SetAttribute("Xp", lv.xp)
	player:SetAttribute("XpToNext", PlayerService.xpToNext(lv.level))

	ClassService.respecLiveStats(player)
	PlayerService.save(player) -- persist immediately; don't wait for autosave

	return true
end

function ClassService.start()
	switchClassRemote = Remotes.getFunction("SwitchClass")
	switchClassRemote.OnServerInvoke = function(player, classId)
		if typeof(classId) ~= "string" then
			return { ok = false, error = "invalid_class" }
		end
		local ok, err = ClassService.switchClass(player, classId)
		return { ok = ok, error = err }
	end

	-- Lets the class-picker UI show every class's own level (e.g. "Mage
	-- Lvl. 3") even for classes the player isn't currently playing.
	local classLevelsRemote = Remotes.getFunction("RequestClassLevels")
	classLevelsRemote.OnServerInvoke = function(player)
		local profile = PlayerService.get(player)
		return profile and profile.classLevels or {}
	end

	local function watchPlayer(player)
		player.CharacterAdded:Connect(function()
			ClassService.applyMovementAndMana(player)
		end)
		if player.Character then
			ClassService.applyMovementAndMana(player)
		end
	end

	Players.PlayerAdded:Connect(watchPlayer)
	-- Players who connected during server boot fired PlayerAdded before the
	-- connect above (same sweep as PlayerService) — without this their walk
	-- speed and class-scaled mana caps stay at the defaults until a respawn.
	for _, player in ipairs(Players:GetPlayers()) do
		watchPlayer(player)
	end

	-- Levels raise HP/Mana caps (see shared/Classes.lua statsAtLevel); hook
	-- into PlayerService's level-up event to re-derive them live.
	PlayerService.registerLevelUpHandler(function(player)
		ClassService.refreshStatsForLevel(player)
	end)
end

return ClassService
