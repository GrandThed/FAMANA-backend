-- Executes server-validated innate dashes (Swift Step / Iron Roll). The
-- character is CLIENT-owned (Roblox network ownership), so the server only
-- validates the cast (mana/cooldown/iframes) and fires InnateDash — the
-- impulse itself happens here. Direction = current move input, falling back
-- to facing, so a stationary dash still goes somewhere sensible.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local DashClient = {}

local activeConn -- one dash at a time; a new one cancels the previous

function DashClient.start()
	local player = Players.LocalPlayer

	Remotes.get("InnateDash").OnClientEvent:Connect(function(params)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not root or not humanoid or humanoid.Health <= 0 then
			return
		end

		local direction = humanoid.MoveDirection
		if direction.Magnitude < 0.1 then
			local look = root.CFrame.LookVector
			direction = Vector3.new(look.X, 0, look.Z)
		end
		if direction.Magnitude < 0.05 then
			return
		end
		direction = direction.Unit

		local speed = (params and params.speed) or 60
		local duration = (params and params.duration) or 0.2

		if activeConn then
			activeConn:Disconnect()
		end
		local elapsed = 0
		activeConn = RunService.Heartbeat:Connect(function(dt)
			elapsed += dt
			if elapsed >= duration or root.Parent == nil then
				activeConn:Disconnect()
				activeConn = nil
				return
			end
			-- Keep gravity's vertical component so dashing off a ledge falls.
			root.AssemblyLinearVelocity = direction * speed
				+ Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
		end)
	end)
end

return DashClient
