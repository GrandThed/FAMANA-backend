-- Classes: Caballero / Arquero / Mago / Clérigo. MVP pass is passive stats
-- only (no active abilities yet). A player can switch class at any time
-- (e.g. via the inventory panel); each class keeps its own level/xp track
-- (see PlayerService), so switching never erases progress on another class.
--
-- Ownership split to avoid systems stepping on each other:
--   * HealthService still owns MaxHealth/Health on spawn (reads the class
--     def itself to scale Config.HP.max).
--   * ManaService still owns the regen tick; it just reads the
--     "ManaRegenAmount" attribute this service sets instead of a fixed
--     constant.
--   * ClassService owns WalkSpeed, Mana caps, the switch-class remote, and
--     the multiplier lookups combat code calls into.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Classes = require(Shared:WaitForChild("Classes"))
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local PlayerService = require(script.Parent.PlayerService)

local ClassService = {}

local BASE_WALK_SPEED = 16 -- Roblox's default Humanoid.WalkSpeed

local switchClassRemote -- RemoteFunction, resolved in start()

local function classDefFor(player)
	local profile = PlayerService.get(player)
	return Classes.get(profile and profile.currentClass)
end

-- ---- lookups used by combat/health/mana systems ---------------------------

function ClassService.getDef(player)
	return classDefFor(player)
end

-- kind: "melee" | "physical" | "magic"
function ClassService.getDamageMult(player, kind)
	return Classes.damageMult(classDefFor(player), kind)
end

function ClassService.getCritBonus(player)
	return classDefFor(player).critChanceBonus
end

function ClassService.getDamageTakenMult(player)
	return classDefFor(player).damageTakenMult
end

-- ---- live stat application -------------------------------------------------

-- Movement + mana caps only (called on spawn). Deliberately does NOT touch
-- Health/MaxHealth — HealthService owns restoring saved HP on spawn and
-- would otherwise race with this.
function ClassService.applyMovementAndMana(player)
	local classDef = classDefFor(player)

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = BASE_WALK_SPEED * classDef.walkSpeedMult
	end

	local maxMana = math.floor(Config.Mana.max * classDef.maxManaMult + 0.5)
	player:SetAttribute("MaxMana", maxMana)
	player:SetAttribute("Mana", maxMana)
	player:SetAttribute("ManaRegenAmount", Config.Mana.regenAmount * classDef.manaRegenMult)
end

-- Full "respec" refresh for an explicit class switch: unlike spawn, this
-- DOES reset Health/Mana to the new class's full amounts — switching class
-- mid-session is a deliberate action, so a clean refill is the expected
-- (and simplest) behavior rather than trying to rescale a partial HP bar.
function ClassService.respecLiveStats(player)
	local classDef = classDefFor(player)

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = BASE_WALK_SPEED * classDef.walkSpeedMult
		local maxHealth = math.floor(Config.HP.max * classDef.hpMult + 0.5)
		humanoid.MaxHealth = maxHealth
		humanoid.Health = maxHealth
	end

	local maxMana = math.floor(Config.Mana.max * classDef.maxManaMult + 0.5)
	player:SetAttribute("MaxMana", maxMana)
	player:SetAttribute("Mana", maxMana)
	player:SetAttribute("ManaRegenAmount", Config.Mana.regenAmount * classDef.manaRegenMult)
end

-- ---- switching --------------------------------------------------------------

-- Returns (ok, errorCode). errorCode is one of "invalid_class" | "not_loaded".
function ClassService.switchClass(player, classId)
	if not Classes.isValid(classId) then
		return false, "invalid_class"
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

	-- Lets the class-picker UI show every class's own level (e.g. "Mago
	-- Lvl. 3") even for classes the player isn't currently playing.
	local classLevelsRemote = Remotes.getFunction("RequestClassLevels")
	classLevelsRemote.OnServerInvoke = function(player)
		local profile = PlayerService.get(player)
		return profile and profile.classLevels or {}
	end

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			ClassService.applyMovementAndMana(player)
		end)
	end)
end

return ClassService
