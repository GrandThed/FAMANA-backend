-- Owns player persistence: load on join (create if new), autosave, save on
-- leave. Holds the authoritative in-memory profile cache for the server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BackendService = require(script.Parent.BackendService)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local PlayerService = {}

-- [userId] = { health, maxHealth, cell, position = {x,y,z}, inventory = {...}, _temporary? }
local cache = {}

local inventoryUpdated -- RemoteEvent
local requestInventory -- RemoteFunction

function PlayerService.get(player)
	return cache[player.UserId]
end

function PlayerService.pushInventory(player)
	local profile = cache[player.UserId]
	if profile and inventoryUpdated then
		inventoryUpdated:FireClient(player, profile.inventory)
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
			cell = Config.cell,
			position = { x = 0, y = 0, z = 0 },
			inventory = {},
			_temporary = true,
		}
	end

	-- This Place represents a specific cell; record it so saves reflect reality.
	data.cell = Config.cell
	cache[userId] = data
	return data
end

-- Add/remove go through the backend (source of truth), then update the cache
-- and notify the client. Used by gathering/combat/drops in later steps.
function PlayerService.addItem(player, itemId, quantity)
	local profile = cache[player.UserId]
	if not profile or profile._temporary then
		return false
	end
	local ok, inventory = BackendService.addItem(player.UserId, itemId, quantity)
	if ok then
		profile.inventory = inventory
		PlayerService.pushInventory(player)
		return true
	end
	return false
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

	-- Client pulls its inventory once its UI is ready.
	requestInventory.OnServerInvoke = function(player)
		local profile = cache[player.UserId]
		return profile and profile.inventory or {}
	end

	-- Load data BEFORE the character spawns so HealthService can restore HP/pos.
	Players.CharacterAutoLoads = false

	Players.PlayerAdded:Connect(function(player)
		loadProfile(player)
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
