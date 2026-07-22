-- Sleeping & Resting Service.
-- Manages lying down on Sleeping Bags ("bolsa_dormir") and Camp Beds ("cama_campamento").
-- Plays resting posture, lowers camera, slowly regenerates HP/Mana, and doubles (2x) the Rested bank rate at night.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local HealthService = require(script.Parent.HealthService)
local ManaService = require(script.Parent.ManaService)

local SleepingService = {}

-- [userId] = { bedPart, bedCFrame, originalCFrame }
local sleepingPlayers = {}

local function notify(player, text)
	Remotes.get("Notify"):FireClient(player, text)
end

function SleepingService.isSleeping(player)
	return sleepingPlayers[player.UserId] ~= nil
end

function SleepingService.wakeUp(player)
	local data = sleepingPlayers[player.UserId]
	if not data then
		return
	end

	sleepingPlayers[player.UserId] = nil

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")

	if humanoid then
		humanoid.PlatformStand = false
	end
	if root then
		root.Anchored = false
		root.CFrame = root.CFrame * CFrame.new(0, 3, 0)
	end

	if humanoid then
		humanoid.PlatformStand = false
	end

	Remotes.get("ToggleSleeping"):FireClient(player, { sleeping = false })
	notify(player, "Te has levantado.")
end

function SleepingService.lieDown(player, bedPart)
	if sleepingPlayers[player.UserId] then
		SleepingService.wakeUp(player)
		return
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")

	if not (humanoid and root and bedPart) then
		return
	end

	local targetCFrame = bedPart.CFrame * CFrame.new(0, 1.2, 0) * CFrame.Angles(math.rad(-90), 0, 0)
	root.CFrame = targetCFrame
	root.Anchored = true
	humanoid.PlatformStand = true

	sleepingPlayers[player.UserId] = {
		bedPart = bedPart,
		bedCFrame = bedPart.CFrame,
	}

	Remotes.get("ToggleSleeping"):FireClient(player, { sleeping = true, bedName = bedPart.Parent and bedPart.Parent.Name or "Cama" })
	notify(player, "Te has acostado a descansar. Presiona E o muévete para levantarte.")
end

function SleepingService.start()
	local toggleSleepingRemote = Remotes.get("ToggleSleeping")

	toggleSleepingRemote.OnServerEvent:Connect(function(player, payload)
		if typeof(payload) == "table" and payload.wakeUp then
			SleepingService.wakeUp(player)
		end
	end)

	-- Periodic HP/Mana regen while sleeping
	task.spawn(function()
		while true do
			task.wait(1)
			for userId, _ in pairs(sleepingPlayers) do
				local player = Players:GetPlayerByUserId(userId)
				if player and player.Character then
					HealthService.heal(player, 3)
					ManaService.add(player, 3)
				else
					sleepingPlayers[userId] = nil
				end
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		sleepingPlayers[player.UserId] = nil
	end)
end

return SleepingService
