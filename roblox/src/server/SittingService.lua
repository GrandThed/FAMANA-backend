-- Sitting Service.
-- Manages sitting down on chairs ("silla_campamento") and benches ("banco_campamento").
-- Sets Humanoid.Sit, welds character to seat, regenerates HP slowly (+1.5 HP/s), and provides a stand-up prompt.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local HealthService = require(script.Parent.HealthService)

local SittingService = {}

-- [userId] = { seatPart, weld }
local seatedPlayers = {}

local function notify(player, text)
	Remotes.get("Notify"):FireClient(player, text)
end

function SittingService.isSeated(player)
	return seatedPlayers[player.UserId] ~= nil
end

function SittingService.standUp(player)
	local data = seatedPlayers[player.UserId]
	if not data then
		return
	end

	seatedPlayers[player.UserId] = nil

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")

	if data.weld then
		data.weld:Destroy()
	end

	if humanoid then
		humanoid.Sit = false
	end

	if root then
		root.Anchored = false
		root.CFrame = root.CFrame * CFrame.new(0, 2.5, 0)
	end

	Remotes.get("ToggleSitting"):FireClient(player, { seated = false })
	notify(player, "Te has levantado del asiento.")
end

function SittingService.sitDown(player, seatPart)
	if seatedPlayers[player.UserId] then
		SittingService.standUp(player)
		return
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")

	if not (humanoid and root and seatPart) then
		return
	end

	local targetCFrame = seatPart.CFrame * CFrame.new(0, 1.2, 0)
	root.CFrame = targetCFrame
	root.Anchored = true
	humanoid.Sit = true

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = seatPart
	weld.Parent = root

	seatedPlayers[player.UserId] = {
		seatPart = seatPart,
		weld = weld,
	}

	Remotes.get("ToggleSitting"):FireClient(player, { seated = true, seatName = seatPart.Parent and seatPart.Parent.Name or "Asiento" })
	notify(player, "Te has sentado. Presiona E, ESPACIO o muévete para levantarte.")
end

function SittingService.start()
	local toggleSittingRemote = Remotes.get("ToggleSitting")

	toggleSittingRemote.OnServerEvent:Connect(function(player, payload)
		if typeof(payload) == "table" and payload.standUp then
			SittingService.standUp(player)
		end
	end)

	-- Periodic HP regen while sitting
	task.spawn(function()
		while true do
			task.wait(1)
			for userId, _ in pairs(seatedPlayers) do
				local player = Players:GetPlayerByUserId(userId)
				if player and player.Character then
					HealthService.heal(player, 1.5)
				else
					seatedPlayers[userId] = nil
				end
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		seatedPlayers[player.UserId] = nil
	end)
end

return SittingService
