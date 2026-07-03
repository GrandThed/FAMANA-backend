-- Owns player persistence: load on join (create if new), autosave, save on
-- leave. Holds the authoritative in-memory profile cache for the server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local BackendService = require(script.Parent.BackendService)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Items = require(Shared:WaitForChild("Items"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local GridConfig = require(Shared:WaitForChild("GridConfig"))

local PlayerService = {}

-- [userId] = { health, maxHealth, gold, cell, position = {x,y,z}, inventory = {...}, _temporary? }
local cache = {}

local inventoryUpdated -- RemoteEvent
local requestInventory -- RemoteFunction

function PlayerService.get(player)
	return cache[player.UserId]
end

-- Server-side listeners notified whenever a player's inventory changes
-- (e.g. ToolService rebuilding hotbar tools). Decouples PlayerService from
-- the systems that react to inventory changes.
local inventoryListeners = {}

function PlayerService.onInventoryChanged(fn)
	table.insert(inventoryListeners, fn)
end

function PlayerService.pushInventory(player)
	local profile = cache[player.UserId]
	if profile and inventoryUpdated then
		inventoryUpdated:FireClient(player, profile.inventory)
	end
	for _, fn in ipairs(inventoryListeners) do
		task.spawn(fn, player)
	end
end

local function loadProfile(player)
	local userId = player.UserId
	local data, err = BackendService.getPlayer(userId)

	if not data and err == "not_found" then
		data = BackendService.createPlayer(userId, player.Name)
	end

	if not data then
		-- Backend unreachable or errored: use a temporary profile so the player
		-- can still play. Marked _temporary so we never persist over real data.
		warn("[PlayerService] Using temporary profile for " .. player.Name .. " (backend unavailable).")
		data = {
			health = Config.HP.max,
			maxHealth = Config.HP.max,
			gold = 0,
			cell = GridConfig.currentCell(),
			position = { x = 0, y = 0, z = 0 },
			inventory = {},
			_temporary = true,
		}
	end

	-- Profiles saved before the gold column existed come back without it.
	data.gold = data.gold or 0
	player:SetAttribute("Gold", data.gold)

	-- Hotbar quick binds (keys 3–0) persist with the profile; the client
	-- seeds its HotbarBinds registry from this attribute.
	data.hotbarBinds = typeof(data.hotbarBinds) == "table" and data.hotbarBinds or {}
	player:SetAttribute("HotbarBinds", HttpService:JSONEncode(data.hotbarBinds))

	-- This Place represents a specific cell; record it so saves reflect reality.
	data.cell = GridConfig.currentCell()

	-- If the player arrived via a border crossing, spawn them at the entry edge
	-- instead of their saved position from the previous cell.
	local joinData = player:GetJoinData()
	local teleportData = joinData and joinData.TeleportData
	if teleportData and teleportData.entryEdge then
		local entry = GridConfig.entryPoint(teleportData.entryEdge)
		data.position = { x = entry.X, y = entry.Y, z = entry.Z }
	end

	cache[userId] = data
	return data
end

-- Add/remove go through the backend (source of truth), then update the cache
-- and notify the client. With `partial`, stackables fill whatever grid space
-- exists (drop pickups). Returns (ok, addedCount).
function PlayerService.addItem(player, itemId, quantity, partial)
	local profile = cache[player.UserId]
	if not profile or profile._temporary then
		return false, 0
	end
	local ok, inventory, added = BackendService.addItem(player.UserId, itemId, quantity, partial)
	if ok and (not partial or (added or 0) > 0) then
		profile.inventory = inventory
		PlayerService.pushInventory(player)
		return true, added or quantity
	end
	return false, 0
end

-- Move a stack between/within containers (the drag & drop verb). The backend
-- validates placement; on success the cache and client are refreshed.
-- Returns (ok, errorCode).
function PlayerService.moveItem(player, from, to)
	local profile = cache[player.UserId]
	if not profile or profile._temporary then
		return false, "offline"
	end
	local ok, inventory, errorCode = BackendService.moveItem(player.UserId, from, to)
	if ok then
		profile.inventory = inventory
		PlayerService.pushInventory(player)
		return true
	end
	return false, errorCode
end

-- Repack the main grid (the Sort button).
function PlayerService.sortInventory(player)
	local profile = cache[player.UserId]
	if not profile or profile._temporary then
		return false
	end
	local ok, inventory = BackendService.sortInventory(player.UserId)
	if ok then
		profile.inventory = inventory
		PlayerService.pushInventory(player)
		return true
	end
	return false
end

-- Re-fetch the inventory from the backend and push it to the client + tools.
-- Used to reflect out-of-band changes (e.g. an admin edit) on an online player.
function PlayerService.refreshInventory(player)
	local profile = cache[player.UserId]
	if not profile or profile._temporary then
		return
	end
	local inventory = BackendService.getInventory(player.UserId)
	if inventory then
		profile.inventory = inventory
		PlayerService.pushInventory(player)
	end
end

function PlayerService.removeItem(player, itemId, quantity)
	local profile = cache[player.UserId]
	if not profile or profile._temporary then
		return false
	end
	local ok, inventory = BackendService.removeItem(player.UserId, itemId, quantity)
	if ok then
		profile.inventory = inventory
		PlayerService.pushInventory(player)
		return true
	end
	return false
end

-- Gold is a live server-authoritative stat (like health): mutate it here,
-- mirror it to the Gold attribute for UI, and let autosave/leave persist it.
function PlayerService.addGold(player, amount)
	local profile = cache[player.UserId]
	if not profile or amount <= 0 then
		return false
	end
	profile.gold = profile.gold + amount
	player:SetAttribute("Gold", profile.gold)
	return true
end

-- Returns false (and changes nothing) if the player can't afford it.
function PlayerService.spendGold(player, amount)
	local profile = cache[player.UserId]
	if not profile or amount <= 0 or profile.gold < amount then
		return false
	end
	profile.gold = profile.gold - amount
	player:SetAttribute("Gold", profile.gold)
	return true
end

local function buildSaveFields(player)
	local profile = cache[player.UserId]
	if not profile then
		return nil
	end

	local character = player.Character
	if character then
		local root = character:FindFirstChild("HumanoidRootPart")
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if root then
			profile.position = { x = root.Position.X, y = root.Position.Y, z = root.Position.Z }
		end
		if humanoid and humanoid.Health > 0 then
			profile.health = math.floor(humanoid.Health + 0.5)
		end
	end

	return {
		health = profile.health,
		gold = profile.gold,
		hotbarBinds = profile.hotbarBinds,
		cell = profile.cell,
		position = profile.position,
	}
end

function PlayerService.save(player)
	local profile = cache[player.UserId]
	if not profile or profile._temporary then
		return
	end
	local fields = buildSaveFields(player)
	if fields then
		BackendService.savePlayer(player.UserId, fields)
	end
end

function PlayerService.start()
	inventoryUpdated = Remotes.get("InventoryUpdated")
	requestInventory = Remotes.getFunction("RequestInventory")

	-- Client pulls its inventory once its UI is ready. The profile loads
	-- asynchronously (backend HTTP), and the client may ask before it's ready,
	-- so wait for it (up to a timeout) instead of returning an empty list.
	requestInventory.OnServerInvoke = function(player)
		local deadline = os.clock() + 10
		while not cache[player.UserId] and os.clock() < deadline do
			task.wait(0.1)
		end
		local profile = cache[player.UserId]
		return profile and profile.inventory or {}
	end

	-- Drag & drop from the client. Arguments are sanitized here (ints only);
	-- real placement validation happens on the backend.
	local moveItem = Remotes.getFunction("MoveItem")
	moveItem.OnServerInvoke = function(player, from, to)
		if typeof(from) ~= "table" or typeof(to) ~= "table" then
			return { ok = false, error = "bad_move" }
		end
		local function sanitize(ref, withRotation)
			local x, y = tonumber(ref.x), tonumber(ref.y)
			local containerId = ref.containerId
			if not x or not y or (containerId ~= "main" and containerId ~= "equipment") then
				return nil
			end
			local safe = { containerId = containerId, x = math.floor(x), y = math.floor(y) }
			if withRotation then
				safe.rotated = ref.rotated == true
			end
			return safe
		end
		local safeFrom = sanitize(from, false)
		local safeTo = sanitize(to, true)
		if not safeFrom or not safeTo then
			return { ok = false, error = "bad_move" }
		end
		local ok, errorCode = PlayerService.moveItem(player, safeFrom, safeTo)
		return { ok = ok, error = errorCode }
	end

	local sortInventory = Remotes.getFunction("SortInventory")
	sortInventory.OnServerInvoke = function(player)
		return { ok = PlayerService.sortInventory(player) }
	end

	-- The client pushes its full quick-bind map on every change; it's
	-- sanitized here and persisted with the next save (autosave/leave).
	local setHotbarBinds = Remotes.get("SetHotbarBinds")
	setHotbarBinds.OnServerEvent:Connect(function(player, payload)
		local profile = cache[player.UserId]
		if not profile or typeof(payload) ~= "table" then
			return
		end
		local clean = {}
		local count = 0
		for key, itemId in pairs(payload) do
			local slot = tonumber(key)
			if slot and slot >= 2 and slot <= 9 and slot == math.floor(slot) and typeof(itemId) == "string" then
				local def = Items.get(itemId)
				if def and (def.type == "tool" or def.type == "consumable") then
					clean[tostring(slot)] = itemId
					count += 1
					if count >= 8 then
						break
					end
				end
			end
		end
		profile.hotbarBinds = clean
	end)

	-- Load data BEFORE the character spawns so HealthService can restore HP/pos.
	Players.CharacterAutoLoads = false

	Players.PlayerAdded:Connect(function(player)
		loadProfile(player)
		-- Push the freshly-loaded inventory in case the client already asked.
		PlayerService.pushInventory(player)
		player:LoadCharacter()
	end)

	Players.PlayerRemoving:Connect(function(player)
		PlayerService.save(player)
		cache[player.UserId] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(Config.autosaveInterval)
			for _, player in ipairs(Players:GetPlayers()) do
				PlayerService.save(player)
			end
		end
	end)

	game:BindToClose(function()
		for _, player in ipairs(Players:GetPlayers()) do
			PlayerService.save(player)
		end
		-- Give the final HTTP saves a moment to flush before shutdown.
		task.wait(2)
	end)
end

return PlayerService
