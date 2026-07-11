-- Crafting: Terraria-style — recipes without a `station` (shared/Recipes)
-- can be crafted anywhere; recipes that need one only unlock near a matching
-- workbench placed in the world (Workbench_<station> markers in authored
-- maps — see shared/MapMarkers — with WORKBENCH_DEFS positions as the
-- no-map fallback). Proximity is recomputed on a slow loop into a `NearbyStations`
-- Player attribute (comma-joined station ids) so the client can show/hide
-- recipes live; the actual craft request re-validates distance server-side,
-- never trusting the attribute.
--
-- CraftItem (RemoteFunction) does the ingredient math: checks the player
-- owns every ingredient (PlayerService.getItemCount), removes them, then
-- adds the result — refunding the ingredients back if the output can't fit
-- (mirrors VendorService's buy-refund-on-no-space flow).

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ArtKit = require(Shared:WaitForChild("ArtKit"))
local Items = require(Shared:WaitForChild("Items"))
local MapMarkers = require(Shared:WaitForChild("MapMarkers"))
local Recipes = require(Shared:WaitForChild("Recipes"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local MeshAssetService = require(script.Parent.MeshAssetService)
local PlayerService = require(script.Parent.PlayerService)

local CraftingService = {}

local STATION_RANGE = 16 -- studs; matches VendorService's MAX_TRADE_DISTANCE
local PROXIMITY_INTERVAL = 1 -- seconds between nearby-station rechecks

-- { station, name, position, facing? (degrees yaw), build? }. Position is a
-- placeholder spot near the vendor/stand cluster — move it once there's a
-- real town layout. Declared further down, once its builder functions exist.

local workbenchFolder
local stationsByType = {} -- [station] = { Vector3 positions, ... }
local notifyRemote

local function groundY(x, z)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { workbenchFolder }
	local result = Workspace:Raycast(Vector3.new(x, 200, z), Vector3.new(0, -1000, 0), params)
	return result and result.Position.Y or 0
end

local function buildTable(def)
	local y = groundY(def.position.X, def.position.Z)
	local origin = CFrame.new(def.position.X, y, def.position.Z) * CFrame.Angles(0, math.rad(def.facing or 0), 0)

	local model = ArtKit.build("Workbench_" .. def.station, origin, {
		{ name = "Top", size = Vector3.new(3.2, 0.3, 1.8), offset = Vector3.new(0, 1.55, 0), color = "trunk", primary = true },
		{ name = "LegA", size = Vector3.new(0.3, 1.5, 0.3), offset = Vector3.new(-1.3, 0.7, -0.7), color = "trunkDark" },
		{ name = "LegB", size = Vector3.new(0.3, 1.5, 0.3), offset = Vector3.new(1.3, 0.7, -0.7), color = "trunkDark" },
		{ name = "LegC", size = Vector3.new(0.3, 1.5, 0.3), offset = Vector3.new(-1.3, 0.7, 0.7), color = "trunkDark" },
		{ name = "LegD", size = Vector3.new(0.3, 1.5, 0.3), offset = Vector3.new(1.3, 0.7, 0.7), color = "trunkDark" },
		{ name = "Brace", size = Vector3.new(2.6, 0.2, 1.3), offset = Vector3.new(0, 0.75, 0), color = "trunkDark" },
	})
	model.Parent = workbenchFolder

	stationsByType[def.station] = stationsByType[def.station] or {}
	table.insert(stationsByType[def.station], model.PrimaryPart.Position)
end

-- Simple Forge: stone furnace with a dark firebox opening and a steel
-- chimney, so it reads as "metalworking" next to the wooden crafting_table.
local function buildForge(def)
	local y = groundY(def.position.X, def.position.Z)
	local origin = CFrame.new(def.position.X, y, def.position.Z) * CFrame.Angles(0, math.rad(def.facing or 0), 0)

	-- Style-A forge mesh when its template loaded. The mesh's mouth faces -Z
	-- while the ArtKit firebox faced +Z, so it spins 180° to keep `facing`
	-- values meaning the same thing. An invisible anchor keeps collision and
	-- the station position registration.
	local mesh = MeshAssetService.place("simple_forge", origin * CFrame.Angles(0, math.rad(180), 0))
	if mesh then
		local model = Instance.new("Model")
		model.Name = "Workbench_" .. def.station
		mesh.Parent = model
		local anchor = Instance.new("Part")
		anchor.Name = "Anchor"
		anchor.Size = Vector3.new(2.6, 1.8, 2.2)
		anchor.CFrame = origin * CFrame.new(0, 0.9, 0)
		anchor.Transparency = 1
		anchor.Anchored = true
		anchor.Parent = model
		model.PrimaryPart = anchor
		model.Parent = workbenchFolder

		stationsByType[def.station] = stationsByType[def.station] or {}
		table.insert(stationsByType[def.station], anchor.Position)
		return
	end

	local model = ArtKit.build("Workbench_" .. def.station, origin, {
		{ name = "Base", size = Vector3.new(2.6, 1.8, 2.2), offset = Vector3.new(0, 0.9, 0), color = "stone", primary = true },
		{ name = "Firebox", size = Vector3.new(1.2, 0.9, 0.4), offset = Vector3.new(0, 0.65, 1.1), color = "stoneDark" },
		{ name = "Ember", size = Vector3.new(0.7, 0.5, 0.1), offset = Vector3.new(0, 0.6, 1.32), color = "gold" },
		{ name = "Chimney", size = Vector3.new(0.7, 1.4, 0.7), offset = Vector3.new(0, 2.5, -0.4), color = "steelDark" },
		{ name = "ChimneyCap", size = Vector3.new(0.9, 0.2, 0.9), offset = Vector3.new(0, 3.3, -0.4), color = "steel" },
	})
	model.Parent = workbenchFolder

	stationsByType[def.station] = stationsByType[def.station] or {}
	table.insert(stationsByType[def.station], model.PrimaryPart.Position)
end

-- Dispatches to the station's own builder (defaults to the table shape, so
-- new stations that don't care about their look still work out of the box).
local function buildWorkbench(def)
	local build = def.build or buildTable
	build(def)
end

local WORKBENCH_DEFS = {
	{ station = "crafting_table", name = "Crafting Table", position = Vector3.new(22, 0, -28), facing = 200, build = buildTable },
	{ station = "simple_forge", name = "Simple Forge", position = Vector3.new(28, 0, -34), facing = 160, build = buildForge },
}

-- Whether `player` currently stands within range of any workbench running
-- `station`. Used both for the live attribute and to re-validate a craft.
local function nearStation(player, station)
	local positions = stationsByType[station]
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not positions or not root then
		return false
	end
	for _, position in ipairs(positions) do
		if (root.Position - position).Magnitude <= STATION_RANGE then
			return true
		end
	end
	return false
end

-- Recomputes every online player's nearby stations and republishes the
-- `NearbyStations` attribute (comma-joined station ids) only when it
-- changed, so it doesn't spam attribute-replication every tick.
local function refreshProximity()
	for _, player in ipairs(Players:GetPlayers()) do
		local near = {}
		for station in pairs(stationsByType) do
			if nearStation(player, station) then
				table.insert(near, station)
			end
		end
		table.sort(near)
		local joined = table.concat(near, ",")
		if player:GetAttribute("NearbyStations") ~= joined then
			player:SetAttribute("NearbyStations", joined)
		end
	end
end

-- registerDoubleCraftChance: fn(player, recipeDef) -> chance the craft
-- produces a second copy for free (the Mage's brewing identity — its
-- callback gates on potion recipes — and future Alchemist gear).
local doubleCraftHooks = {}
function CraftingService.registerDoubleCraftChance(fn)
	table.insert(doubleCraftHooks, fn)
end

local function hookedDoubleCraftChance(player, recipeDef)
	local sum = 0
	for _, fn in ipairs(doubleCraftHooks) do
		local ok, value = pcall(fn, player, recipeDef)
		if ok and typeof(value) == "number" then
			sum += value
		end
	end
	return sum
end

local function craftMessage(def)
	local quantity = def.result.quantity
	local resultDef = Items.get(def.result.itemId)
	local label = resultDef and resultDef.name or def.result.itemId
	if quantity > 1 then
		label = quantity .. "x " .. label
	end
	return "Crafted " .. label
end

local function handleCraft(player, recipeId)
	if typeof(recipeId) ~= "string" then
		return { ok = false, error = "bad_request" }
	end
	local def = Recipes.get(recipeId)
	if not def then
		return { ok = false, error = "unknown_recipe" }
	end
	if def.station and not nearStation(player, def.station) then
		return { ok = false, error = "too_far" }
	end

	for _, ingredient in ipairs(def.ingredients) do
		if PlayerService.getItemCount(player, ingredient.itemId) < ingredient.quantity then
			return { ok = false, error = "missing_materials" }
		end
	end

	-- Remove first; ingredient counts were just verified above so failure
	-- here would only happen from a race (e.g. dropped mid-craft), which is
	-- rare enough that the loop stops rather than trying to be atomic.
	local removed = {}
	for _, ingredient in ipairs(def.ingredients) do
		if not PlayerService.removeItem(player, ingredient.itemId, ingredient.quantity) then
			-- Refund whatever was already taken and bail.
			for _, back in ipairs(removed) do
				PlayerService.addItem(player, back.itemId, back.quantity)
			end
			return { ok = false, error = "missing_materials" }
		end
		table.insert(removed, ingredient)
	end

	local ok = PlayerService.addItem(player, def.result.itemId, def.result.quantity)
	if not ok then
		for _, back in ipairs(removed) do
			PlayerService.addItem(player, back.itemId, back.quantity)
		end
		return { ok = false, error = "no_space" }
	end

	if notifyRemote then
		notifyRemote:FireClient(player, craftMessage(def))
	end

	-- Double-craft roll (the Mage's brewing identity + future Alchemist
	-- gear): a second copy of the output, free. Silent on no-space — the
	-- paid-for craft already landed.
	if math.random() < hookedDoubleCraftChance(player, def) then
		if PlayerService.addItem(player, def.result.itemId, def.result.quantity) and notifyRemote then
			notifyRemote:FireClient(player, "Double craft!")
		end
	end
	return { ok = true }
end

function CraftingService.start()
	notifyRemote = Remotes.get("Notify")

	workbenchFolder = Instance.new("Folder")
	workbenchFolder.Name = "Workbenches"
	workbenchFolder.Parent = Workspace

	if MapMarkers.mapPresent() then
		local defsByStation = {}
		for _, def in ipairs(WORKBENCH_DEFS) do
			defsByStation[def.station] = def
		end
		local markers = MapMarkers.takeFor("Workbench_", defsByStation)
		for station, def in pairs(defsByStation) do
			for _, marker in ipairs(markers[station] or {}) do
				buildWorkbench({
					station = def.station,
					name = def.name,
					position = marker.cframe.Position,
					facing = MapMarkers.facing(marker),
					build = def.build,
				})
			end
		end
	else
		for _, def in ipairs(WORKBENCH_DEFS) do
			buildWorkbench(def)
		end
	end

	Players.PlayerRemoving:Connect(function(player)
		player:SetAttribute("NearbyStations", nil)
	end)

	task.spawn(function()
		while true do
			refreshProximity()
			task.wait(PROXIMITY_INTERVAL)
		end
	end)

	local craftItem = Remotes.getFunction("CraftItem")
	craftItem.OnServerInvoke = handleCraft
end

return CraftingService
