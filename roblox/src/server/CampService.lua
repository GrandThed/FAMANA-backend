-- Acampada: crafting the "acampada" item (shared/Recipes.lua) lets a player
-- plant a camp — a safe zone + respawn point for them AND their current
-- party (checked live via the PartyId attribute, not a frozen member list:
-- someone who joins later is covered, someone who leaves loses it right
-- away). In-memory only, not persisted across server restarts — same
-- philosophy as PartyService, a live session concept rather than save data.
--
-- Placement: PlaceAcampada (RemoteFunction) takes a ground (x, z); the
-- client only sends intent, the server re-validates distance and item
-- ownership before consuming it (same pattern as CraftingService.CraftItem).
-- One active camp per owner at a time; placing costs exactly 1x "acampada".
--
-- Safety + respawn hook into HealthService (see registerDamageImmunity /
-- registerSpawnPositionOverride there) rather than HealthService requiring
-- this module — keeps the dependency one-directional.
--
-- Client flow: the "acampada" item is `type = "placeable"` (EQUIPPABLE in
-- ToolService), so it becomes a held Tool like any weapon/tool. The client
-- (client/CampPlacementUI.lua) shows a ground preview while it's equipped
-- and calls PlaceAcampada on click — see that file for the aiming part.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local ArtKit = require(Shared:WaitForChild("ArtKit"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local PlayerService = require(script.Parent.PlayerService)
local HealthService = require(script.Parent.HealthService)
local DayNightService = require(script.Parent.DayNightService)

local CampService = {}

local CAMP = Config.Camp
local ZONE_HALF = CAMP.zoneSize / 2

-- [ownerUserId] = { center = Vector3, model = Model, partyId = number|nil, expiresAt = os.clock() }
local camps = {}
-- [ownerUserId] = os.clock() before which that owner can't place another camp
local cooldownUntil = {}
-- Called with (ownerUserId, camp) right after a camp is torn down (expired
-- or otherwise) — CampFurnitureService uses this to clean up/return
-- furniture planted inside it. See CampService.onTeardown.
local teardownListeners = {}
-- Called with (ownerUserId, camp, player) right after a camp is placed —
-- CampFurnitureService uses this to restore that owner's saved furniture
-- layout. See CampService.onPlace.
local placeListeners = {}

local campFolder
local notifyRemote

local function notify(player, message)
	if player and notifyRemote then
		notifyRemote:FireClient(player, message)
	end
end

-- Finds the camp (if any) protecting this player: their own, or the one
-- belonging to whoever in their current party planted one.
local function campFor(player)
	local mine = camps[player.UserId]
	if mine then
		return mine
	end
	local myPartyId = player:GetAttribute("PartyId")
	if not myPartyId then
		return nil
	end
	for _, camp in pairs(camps) do
		if camp.partyId == myPartyId then
			return camp
		end
	end
	return nil
end

-- Public: the camp instance for a given owner (nil if they don't have one
-- active right now). Used by CampFurnitureService for periodic layout
-- autosave and by the client-facing timer (CampService.getTimer).
function CampService.getCamp(ownerUserId)
	return camps[ownerUserId]
end

-- Public: { active, remaining, duration } for the camp campFor(player) sees
-- (their own, or their party's). Poll-based by design — remaining is
-- "seconds left as of this call", no client/server clock sync needed; the
-- client re-polls periodically and extrapolates locally between polls.
function CampService.getTimer(player)
	local camp = campFor(player)
	if not camp then
		return { active = false }
	end
	local remaining = camp.expiresAt - os.clock()
	if remaining <= 0 then
		return { active = false }
	end
	return { active = true, remaining = remaining, duration = CAMP.duration }
end

-- Public: the camp (if any) this player can plant furniture / access shared
-- storage in — same reach as CampService.isPositionSafeForPlayer (own camp,
-- or their current party's). CampFurnitureService uses this instead of
-- reimplementing the owner-or-party lookup.
function CampService.campFor(player)
	return campFor(player)
end

-- Public: half the zone's side length in studs (a camp's safe/buildable area
-- is a `zoneSize` x `zoneSize` square centered on `camp.center`).
CampService.ZONE_HALF = ZONE_HALF

-- Public: register a callback fired right after ANY camp is torn down
-- (expired, or a future manual teardown), with (ownerUserId, camp) — the
-- camp table is already detached from `camps` at this point but still has
-- `center`/`partyId`/`ownerUserId`, so listeners can e.g. drop leftover
-- chest contents at camp.center before it's gone for good.
function CampService.onTeardown(fn)
	table.insert(teardownListeners, fn)
end

-- Public: register a callback fired right after a camp is successfully
-- placed, with (ownerUserId, camp, player) — see CampService.onTeardown for
-- the symmetric teardown hook.
function CampService.onPlace(fn)
	table.insert(placeListeners, fn)
end

-- Public: used by combat systems that want to short-circuit their own damage
-- math too (most should just rely on the HealthService hook below instead).
function CampService.isPositionSafeForPlayer(player, position)
	local camp = campFor(player)
	if not camp then
		return false
	end
	local dx = math.abs(position.X - camp.center.X)
	local dz = math.abs(position.Z - camp.center.Z)
	return dx <= ZONE_HALF and dz <= ZONE_HALF
end

local function findGroundY(x, z)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { campFolder }
	local result = Workspace:Raycast(Vector3.new(x, 300, z), Vector3.new(0, -1000, 0), params)
	return result and result.Position.Y or 0
end

-- Translucent floor marking the zone + four fence posts/rails at the
-- corners (visual only — safety is enforced by isPositionSafeForPlayer, not
-- collision, so none of this blocks movement) + a small campfire at center.
local function buildCampModel(center)
	local origin = CFrame.new(center)
	local edge = ZONE_HALF - 0.5

	local model = ArtKit.build("Acampada", origin, {
		{
			name = "Zone",
			size = Vector3.new(CAMP.zoneSize, 0.2, CAMP.zoneSize),
			offset = Vector3.new(0, 0.1, 0),
			color = "leafLight",
			transparency = 0.65,
			canCollide = false,
			primary = true,
		},
		{ name = "PostA", size = Vector3.new(0.6, 4, 0.6), offset = Vector3.new(edge, 2, edge), color = "trunkDark", canCollide = false },
		{ name = "PostB", size = Vector3.new(0.6, 4, 0.6), offset = Vector3.new(-edge, 2, edge), color = "trunkDark", canCollide = false },
		{ name = "PostC", size = Vector3.new(0.6, 4, 0.6), offset = Vector3.new(edge, 2, -edge), color = "trunkDark", canCollide = false },
		{ name = "PostD", size = Vector3.new(0.6, 4, 0.6), offset = Vector3.new(-edge, 2, -edge), color = "trunkDark", canCollide = false },
		{ name = "RailN", size = Vector3.new(CAMP.zoneSize - 1, 0.3, 0.3), offset = Vector3.new(0, 2.5, edge), color = "trunkDark", canCollide = false },
		{ name = "RailS", size = Vector3.new(CAMP.zoneSize - 1, 0.3, 0.3), offset = Vector3.new(0, 2.5, -edge), color = "trunkDark", canCollide = false },
		{ name = "RailE", size = Vector3.new(0.3, 0.3, CAMP.zoneSize - 1), offset = Vector3.new(edge, 2.5, 0), color = "trunkDark", canCollide = false },
		{ name = "RailW", size = Vector3.new(0.3, 0.3, CAMP.zoneSize - 1), offset = Vector3.new(-edge, 2.5, 0), color = "trunkDark", canCollide = false },
		{ name = "LogA", size = Vector3.new(2, 0.5, 0.5), offset = Vector3.new(0, 0.4, 0), rot = Vector3.new(0, 35, 0), color = "trunk", canCollide = false },
		{ name = "LogB", size = Vector3.new(2, 0.5, 0.5), offset = Vector3.new(0, 0.4, 0), rot = Vector3.new(0, -35, 0), color = "trunk", canCollide = false },
		{ name = "Ember", shape = "Ball", size = Vector3.new(1, 0.6, 1), offset = Vector3.new(0, 0.7, 0), color = "gold", canCollide = false },
	})

	local ember = model:FindFirstChild("Ember")
	if ember then
		local light = Instance.new("PointLight")
		light.Color = ArtKit.Palette.gold
		light.Range = 20
		light.Brightness = 2
		light.Parent = ember
	end

	model.Parent = campFolder
	return model
end

function CampService.teardown(userId, reason)
	local camp = camps[userId]
	if not camp then
		return
	end
	camps[userId] = nil
	cooldownUntil[userId] = os.clock() + CAMP.cooldown
	if camp.model then
		camp.model:Destroy()
	end

	for _, listener in ipairs(teardownListeners) do
		local ok, err = pcall(listener, userId, camp)
		if not ok then
			warn("[CampService] teardown listener error: " .. tostring(err))
		end
	end

	if reason == "expired" then
		local owner = Players:GetPlayerByUserId(userId)
		notify(owner, "Your camp expired — you can place another in " .. math.floor(CAMP.cooldown / 60) .. " min.")
	end
end

local function handlePlace(player, x, z)
	if typeof(x) ~= "number" or typeof(z) ~= "number" then
		return { ok = false, error = "bad_request" }
	end

	local userId = player.UserId
	if camps[userId] then
		notify(player, "You already have an active camp.")
		return { ok = false, error = "already_active" }
	end

	local cooldown = cooldownUntil[userId]
	if cooldown and cooldown > os.clock() then
		notify(player, "Camp on cooldown — " .. math.ceil((cooldown - os.clock()) / 60) .. " min left.")
		return { ok = false, error = "cooldown", remaining = cooldown - os.clock() }
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return { ok = false, error = "no_character" }
	end

	-- Anti-exploit: re-check distance server-side, never trust the client's
	-- claimed placement point (same posture as CraftingService/ToolService).
	local flatDistance = (Vector3.new(x, root.Position.Y, z) - root.Position).Magnitude
	if flatDistance > CAMP.maxPlacementDistance then
		notify(player, "Too far away to place it there.")
		return { ok = false, error = "too_far" }
	end

	if PlayerService.getItemCount(player, "acampada") < 1 then
		notify(player, "You don't have an Acampada to place.")
		return { ok = false, error = "missing_item" }
	end
	if not PlayerService.removeItem(player, "acampada", 1) then
		notify(player, "You don't have an Acampada to place.")
		return { ok = false, error = "missing_item" }
	end

	local center = Vector3.new(x, findGroundY(x, z), z)
	local model = buildCampModel(center)
	local expiresAt = os.clock() + CAMP.duration

	camps[userId] = {
		center = center,
		model = model,
		partyId = player:GetAttribute("PartyId"),
		expiresAt = expiresAt,
		ownerUserId = userId,
	}

	task.delay(CAMP.duration, function()
		local camp = camps[userId]
		-- Only tear down if this is still the same camp (guards against a
		-- weird replace/edge case rather than nuking a newer one).
		if camp and camp.expiresAt == expiresAt then
			CampService.teardown(userId, "expired")
		end
	end)

	notify(player, "Camp placed — safe zone for " .. math.floor(CAMP.duration / 60) .. " min.")

	local camp = camps[userId]
	for _, listener in ipairs(placeListeners) do
		local ok, err = pcall(listener, userId, camp, player)
		if not ok then
			warn("[CampService] place listener error: " .. tostring(err))
		end
	end

	return { ok = true }
end

function CampService.start()
	notifyRemote = Remotes.get("Notify")

	campFolder = Instance.new("Folder")
	campFolder.Name = "Camps"
	campFolder.Parent = Workspace

	HealthService.registerDamageImmunity(function(player)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root then
			return false
		end
		return CampService.isPositionSafeForPlayer(player, root.Position)
	end)

	HealthService.registerSpawnPositionOverride(function(player)
		local camp = campFor(player)
		if not camp then
			return nil
		end
		-- Spawn just off the fire, not inside the embers.
		return camp.center + Vector3.new(0, 3, ZONE_HALF / 2)
	end)

	-- The ember's PointLight is always on (buildCampModel), but the warmth
	-- only matters when it's actually dark out — during the day the safe
	-- zone's damage immunity is already the whole reward. Same
	-- isPositionSafeForPlayer check as the immunity hook above.
	HealthService.registerBonusRegen(function(player)
		if not DayNightService.isNight() then
			return 0
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root or not CampService.isPositionSafeForPlayer(player, root.Position) then
			return 0
		end
		return CAMP.nightRegenBonus
	end)

	local placeAcampada = Remotes.getFunction("PlaceAcampada")
	placeAcampada.OnServerInvoke = handlePlace

	local getCampTimer = Remotes.getFunction("GetCampTimer")
	getCampTimer.OnServerInvoke = CampService.getTimer
end

return CampService