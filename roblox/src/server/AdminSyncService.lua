-- Polls the backend for pending player events (e.g. admin inventory or stats
-- edits) and applies them live: refreshes the affected player's inventory or
-- profile stats and shows them a notification. This is what makes admin-panel
-- changes appear in-game without a rejoin. (A MessagingService/Open Cloud push
-- could replace polling later for instant delivery in the published game.)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BackendService = require(script.Parent.BackendService)
local PlayerService = require(script.Parent.PlayerService)
local ClassService = require(script.Parent.ClassService)

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
			elseif event.kind == "stats" then
				local applied, classChanged = PlayerService.applyStats(player, event.payload)
				if applied then
					if classChanged then
						-- Same full refresh as a player-initiated class switch:
						-- new class's HP/mana caps + walk speed, refilled.
						ClassService.respecLiveStats(player)
					end
					print("[AdminSyncService] applied admin stats for " .. player.Name)
				else
					-- Loud on purpose: a silent skip here means the next
					-- autosave overwrites the admin's edit in the DB.
					warn(
						"[AdminSyncService] could NOT apply admin stats for "
							.. player.Name
							.. " (profile not loaded / temporary, or bad payload)"
					)
				end
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
