-- Polls the backend for pending player events (e.g. admin inventory edits) and
-- applies them live: refreshes the affected player's inventory and shows them a
-- notification. This is what makes admin-panel changes appear in-game without a
-- rejoin. (A MessagingService/Open Cloud push could replace polling later for
-- instant delivery in the published game.)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BackendService = require(script.Parent.BackendService)
local PlayerService = require(script.Parent.PlayerService)

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local AdminSyncService = {}

local POLL_INTERVAL = 4 -- seconds

local notifyRemote

local function poll()
	local players = Players:GetPlayers()
	if #players == 0 then
		return
	end

	local userIds = {}
	for _, player in ipairs(players) do
		table.insert(userIds, player.UserId)
	end

	local events = BackendService.pollEvents(userIds)
	if not events then
		return
	end

	for _, event in ipairs(events) do
		local player = Players:GetPlayerByUserId(tonumber(event.playerId))
		if player then
			if event.kind == "inventory" then
				PlayerService.refreshInventory(player)
			end
			if event.message then
				notifyRemote:FireClient(player, event.message)
			end
		end
	end
end

function AdminSyncService.start()
	notifyRemote = Remotes.get("Notify")

	task.spawn(function()
		while true do
			task.wait(POLL_INTERVAL)
			local ok, err = pcall(poll)
			if not ok then
				warn("[AdminSyncService] poll error: " .. tostring(err))
			end
		end
	end)
end

return AdminSyncService
