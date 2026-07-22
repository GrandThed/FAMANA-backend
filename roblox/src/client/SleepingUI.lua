-- Sleeping UI.
-- Displays resting overlay hint and handles camera transition while lying down on a bed.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)

local player = Players.LocalPlayer

local SleepingUI = {}

function SleepingUI.start()
	local toggleSleepingRemote = Remotes.get("ToggleSleeping")

	local gui = Instance.new("ScreenGui")
	gui.Name = "SleepingUI"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 9
	gui.Parent = player:WaitForChild("PlayerGui")

	local hintFrame = Instance.new("Frame")
	hintFrame.Size = UDim2.new(0, 340, 0, 48)
	hintFrame.Position = UDim2.new(0.5, 0, 0.85, 0)
	hintFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	hintFrame.Visible = false
	hintFrame.Parent = gui
	UIKit.stylePanel(hintFrame)
	UIKit.addShadow(hintFrame)

	local hintLabel = UIKit.label(
		hintFrame,
		"😴 Descansando... Presiona E o ESPACIO para levantarte",
		13,
		Theme.Semantic.Currency,
		Theme.Font.BodyBold
	)
	hintLabel.Size = UDim2.new(1, -20, 1, 0)
	hintLabel.Position = UDim2.new(0, 10, 0, 0)
	hintLabel.TextXAlignment = Enum.TextXAlignment.Center

	local isSleeping = false

	toggleSleepingRemote.OnClientEvent:Connect(function(payload)
		if typeof(payload) ~= "table" then
			return
		end
		isSleeping = payload.sleeping == true
		hintFrame.Visible = isSleeping
	end)

	local function requestWakeUp()
		if isSleeping then
			toggleSleepingRemote:FireServer({ wakeUp = true })
		end
	end

	UserInputService.InputBegan:Connect(function(input, gpe)
		if not isSleeping then
			return
		end
		local k = input.KeyCode
		if k == Enum.KeyCode.E or k == Enum.KeyCode.Space or k == Enum.KeyCode.W or k == Enum.KeyCode.A or k == Enum.KeyCode.S or k == Enum.KeyCode.D or k == Enum.KeyCode.Up or k == Enum.KeyCode.Down or k == Enum.KeyCode.Left or k == Enum.KeyCode.Right then
			requestWakeUp()
		end
	end)

	local RunService = game:GetService("RunService")
	RunService.Heartbeat:Connect(function()
		if not isSleeping then
			return
		end
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum and (hum.MoveDirection.Magnitude > 0.1 or hum.Jump) then
			requestWakeUp()
		end
	end)
end

return SleepingUI
