-- Toast notifications, top-center. Driven by the server's "Notify" RemoteEvent
-- (e.g. when an admin edits your inventory). Toasts stack and auto-dismiss.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local player = Players.LocalPlayer

local NotificationUI = {}

local HOLD = 4 -- seconds a toast stays before fading

function NotificationUI.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "NotificationUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 500
	gui.Parent = player:WaitForChild("PlayerGui")

	local list = Instance.new("Frame")
	list.Size = UDim2.new(0, 360, 1, -20)
	list.Position = UDim2.new(0.5, 0, 0, 12)
	list.AnchorPoint = Vector2.new(0.5, 0)
	list.BackgroundTransparency = 1
	list.Parent = gui

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 6)
	layout.Parent = list

	local function toast(message)
		local frame = Instance.new("Frame")
		frame.Size = UDim2.new(1, 0, 0, 40)
		frame.BackgroundColor3 = Color3.fromRGB(35, 40, 55)
		frame.BackgroundTransparency = 1
		frame.BorderSizePixel = 0
		frame.Parent = list

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = frame

		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, -20, 1, 0)
		label.Position = UDim2.new(0, 10, 0, 0)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamMedium
		label.TextSize = 14
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextTransparency = 1
		label.TextWrapped = true
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Text = message
		label.Parent = frame

		local fadeIn = TweenInfo.new(0.25)
		TweenService:Create(frame, fadeIn, { BackgroundTransparency = 0.1 }):Play()
		TweenService:Create(label, fadeIn, { TextTransparency = 0 }):Play()

		task.delay(HOLD, function()
			local fadeOut = TweenInfo.new(0.4)
			TweenService:Create(frame, fadeOut, { BackgroundTransparency = 1 }):Play()
			local out = TweenService:Create(label, fadeOut, { TextTransparency = 1 })
			out:Play()
			out.Completed:Once(function()
				frame:Destroy()
			end)
		end)
	end

	Remotes.get("Notify").OnClientEvent:Connect(toast)
end

return NotificationUI
