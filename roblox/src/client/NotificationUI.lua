-- Toast notifications, center-right. Driven by the server's "Notify" RemoteEvent
-- (e.g. when an admin edits your inventory). Toasts stack downward from the
-- vertical center and auto-dismiss. Slides further right while the inventory
-- panel is open so the two don't overlap.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
local ClientState = require(script.Parent.ClientState)
local InventoryUI = require(script.Parent.InventoryUI)

local player = Players.LocalPlayer

local NotificationUI = {}

local HOLD = 4 -- seconds a toast stays before fading
local LIST_WIDTH = 360
local DODGE_GAP = 24 -- breathing room between the inventory panel and the toasts
local DODGE_TWEEN = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

function NotificationUI.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "NotificationUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 500
	gui.Parent = player:WaitForChild("PlayerGui")

	local list = Instance.new("Frame")
	list.Size = UDim2.new(0, LIST_WIDTH, 0, 400)
	list.Position = UDim2.new(0.78, 18, 0.5, 0)
	list.AnchorPoint = Vector2.new(1, 0.5)
	list.BackgroundTransparency = 1
	list.Parent = gui

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 4)
	layout.Parent = list

	local NORMAL_POS = list.Position
	-- Right edge of the inventory panel (it's screen-centered) plus a gap,
	-- then this list's own width, since AnchorPoint.X = 1 positions by its
	-- right edge. Falls back to a sane width if InventoryUI hasn't set
	-- panelWidth yet for some reason.
	local function dodgedPos()
		local halfPanel = (InventoryUI.panelWidth or 728) / 2
		return UDim2.new(0.5, halfPanel + DODGE_GAP + LIST_WIDTH, 0.5, 0)
	end

	-- ClientState is a plain table (no change signal), so poll it like the
	-- other controllers (e.g. TargetingController) do.
	local dodged = false
	RunService.RenderStepped:Connect(function()
		if ClientState.inventoryOpen ~= dodged then
			dodged = ClientState.inventoryOpen
			TweenService:Create(list, DODGE_TWEEN, { Position = dodged and dodgedPos() or NORMAL_POS }):Play()
		end
	end)

	local function toast(message)
		local frame = Instance.new("Frame")
		frame.Size = UDim2.new(1, 0, 0, 0) -- Starts at height 0 to enable smooth entry slide
		frame.BackgroundTransparency = 1
		frame.BorderSizePixel = 0
		frame.ClipsDescendants = true -- Hides the label as the frame height changes
		frame.Parent = list

		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, 0, 0, 24) -- Retains a fixed height to avoid text wrapping changes
		label.Position = UDim2.new(0, 10, 0, 8) -- Starts a bit low, slides up into place
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.TextSize = 16
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextTransparency = 1
		label.TextStrokeTransparency = 0.1 -- no background now, so lean on the stroke for legibility
		label.TextWrapped = true
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Text = message
		label.Parent = frame

		local fadeIn = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(frame, fadeIn, { Size = UDim2.new(1, 0, 0, 24) }):Play()
		TweenService:Create(label, fadeIn, { TextTransparency = 0, Position = UDim2.new(0, 0, 0, 0) }):Play()

		task.delay(HOLD, function()
			local fadeOut = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			local outLabel = TweenService:Create(label, fadeOut, { TextTransparency = 1 })
			local outFrame = TweenService:Create(frame, fadeOut, { Size = UDim2.new(1, 0, 0, 0) })
			
			outLabel:Play()
			outFrame:Play()
			
			outLabel.Completed:Once(function()
				frame:Destroy()
			end)
		end)
	end

	Remotes.get("Notify").OnClientEvent:Connect(toast)
end

return NotificationUI
