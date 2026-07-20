-- Leaderboard panel (T key / top-right button): top 20 players by level,
-- gold, or bestiary kills, with tabs to switch metric. Unlike Bestiary/
-- Achievements this genuinely needs a server round-trip — rankings are
-- global (every player, not just the local one), so it invokes the
-- "GetLeaderboard" RemoteFunction (LeaderboardService, which itself proxies
-- to backend/src/routes/leaderboards.js with a short cache).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)
local TopRightMenu = require(script.Parent.TopRightMenu)
local Sfx = require(script.Parent.Sfx)

local player = Players.LocalPlayer

local LeaderboardUI = {}

local COLORS = {
	section = Theme.Semantic.SurfaceWell,
	line = Theme.Semantic.BorderHair,
	tile = Theme.Color.Ink900,
	accent = Theme.Color.Ember300,
	text = Theme.Semantic.TextBody,
	textDim = Theme.Semantic.TextMuted,
}

local TABS = {
	{ type = "level", label = "Level" },
	{ type = "gold", label = "Gold" },
	{ type = "kills", label = "Kills" },
}

local PANEL_W = 420
local PANEL_H = 520

local function makeLabel(parent, text, size, color, font)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.FontFace = font or Theme.Font.Body
	label.TextSize = size
	label.TextColor3 = color or COLORS.text
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = text
	label.Parent = parent
	return label
end

function LeaderboardUI.start()
	local getLeaderboard = Remotes.getFunction("GetLeaderboard")

	local gui = Instance.new("ScreenGui")
	gui.Name = "LeaderboardUI"
	gui.ResetOnSpawn = false
	gui.Enabled = true
	gui.DisplayOrder = 5
	gui.Parent = player:WaitForChild("PlayerGui")

	local panel = Instance.new("Frame")
	panel.Size = UDim2.new(0, PANEL_W, 0, PANEL_H)
	panel.Position = UDim2.new(0.5, 0, 0.5, 0)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Visible = false
	panel.Parent = gui
	UIKit.stylePanel(panel)
	UIKit.addShadow(panel)
	UIKit.autoScale(panel)

	local title = makeLabel(panel, "Leaderboard", Theme.Text.Title, Theme.Semantic.TextTitle, Theme.Font.DisplayBold)
	title.Size = UDim2.new(1, -80, 0, 30)
	title.Position = UDim2.new(0, 12, 0, 4)

	local closeBtn = UIKit.closeButton(panel)
	closeBtn.Position = UDim2.new(1, -6, 0, 6)
	closeBtn.AnchorPoint = Vector2.new(1, 0)

	local tabBar = Instance.new("Frame")
	tabBar.Size = UDim2.new(1, -24, 0, 28)
	tabBar.Position = UDim2.new(0, 12, 0, 38)
	tabBar.BackgroundTransparency = 1
	tabBar.Parent = panel

	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.Padding = UDim.new(0, 6)
	tabLayout.Parent = tabBar

	local list = Instance.new("ScrollingFrame")
	list.Size = UDim2.new(1, -24, 1, -102)
	list.Position = UDim2.new(0, 12, 0, 74)
	list.BackgroundColor3 = COLORS.section
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new(0, 0, 0, 0)
	list.Parent = panel

	local listStroke = Instance.new("UIStroke")
	listStroke.Thickness = 1
	listStroke.Color = COLORS.line
	listStroke.Parent = list

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 3)
	layout.Parent = list

	local listPadding = Instance.new("UIPadding")
	listPadding.PaddingTop = UDim.new(0, 6)
	listPadding.PaddingLeft = UDim.new(0, 8)
	listPadding.PaddingRight = UDim.new(0, 8)
	listPadding.PaddingBottom = UDim.new(0, 6)
	listPadding.Parent = list

	local statusLabel = makeLabel(panel, "", 12, COLORS.textDim)
	statusLabel.Size = UDim2.new(1, -24, 0, 16)
	statusLabel.Position = UDim2.new(0, 12, 1, -22)
	statusLabel.TextXAlignment = Enum.TextXAlignment.Center

	local activeType = TABS[1].type
	local tabButtons = {}

	local function row(order, rank, username, score)
		local frame = Instance.new("Frame")
		frame.Size = UDim2.new(1, 0, 0, 22)
		frame.BackgroundTransparency = rank <= 3 and 0.7 or 1
		frame.BackgroundColor3 = COLORS.tile
		frame.BorderSizePixel = 0
		frame.LayoutOrder = order
		frame.Parent = list

		local rankLabel = makeLabel(frame, "#" .. rank, 13, rank <= 3 and COLORS.accent or COLORS.textDim, Theme.Font.BodyBold)
		rankLabel.Size = UDim2.new(0, 36, 1, 0)

		local nameLabel = makeLabel(frame, username, 13, COLORS.text)
		nameLabel.Size = UDim2.new(1, -120, 1, 0)
		nameLabel.Position = UDim2.new(0, 36, 0, 0)
		nameLabel.TextTruncate = Enum.TextTruncate.AtEnd

		local scoreLabel = makeLabel(frame, tostring(score), 13, COLORS.text, Theme.Font.BodyBold)
		scoreLabel.Size = UDim2.new(0, 80, 1, 0)
		scoreLabel.Position = UDim2.new(1, -80, 0, 0)
		scoreLabel.TextXAlignment = Enum.TextXAlignment.Right

		return frame
	end

	local requestId = 0
	local function load(metricType)
		activeType = metricType
		for _, btn in pairs(tabButtons) do
			local isActive = btn:GetAttribute("MetricType") == metricType
			btn.BackgroundTransparency = isActive and 0 or 0.85
			(btn:FindFirstChildOfClass("TextLabel") or btn).TextColor3 = isActive and COLORS.accent or COLORS.textDim
		end

		for _, child in ipairs(list:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		statusLabel.Text = "Loading…"

		requestId += 1
		local thisRequest = requestId
		task.spawn(function()
			local ok, result = pcall(function()
				return getLeaderboard:InvokeServer(metricType)
			end)
			if thisRequest ~= requestId then
				return -- a newer tab switch/refresh already superseded this
			end
			if not ok or not result or not result.entries then
				statusLabel.Text = "Couldn't load the leaderboard. Try again shortly."
				return
			end
			if #result.entries == 0 then
				statusLabel.Text = "No entries yet."
				return
			end
			statusLabel.Text = ""
			for i, entry in ipairs(result.entries) do
				row(i, entry.rank, entry.username, entry.score)
			end
		end)
	end

	for _, tab in ipairs(TABS) do
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(0, 90, 1, 0)
		btn.BackgroundColor3 = COLORS.tile
		btn.BackgroundTransparency = 0.85
		btn.BorderSizePixel = 0
		btn.AutoButtonColor = false
		btn.Text = ""
		btn:SetAttribute("MetricType", tab.type)
		btn.Parent = tabBar

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 6)
		corner.Parent = btn

		local btnLabel = makeLabel(btn, tab.label, 13, COLORS.textDim, Theme.Font.BodyBold)
		btnLabel.Size = UDim2.new(1, 0, 1, 0)
		btnLabel.TextXAlignment = Enum.TextXAlignment.Center

		btn.Activated:Connect(function()
			load(tab.type)
		end)
		tabButtons[tab.type] = btn
	end

	local isOpen = false
	local function setOpen(open)
		isOpen = open
		Sfx.play(isOpen and "panelOpen" or "panelClose")
		panel.Visible = isOpen
		if isOpen then
			load(activeType)
		end
	end

	local function toggle()
		setOpen(not isOpen)
	end

	local openBtn = TopRightMenu.addButton("Leaderboard (T)", 9)
	openBtn.Name = "LeaderboardButton"
	openBtn.Activated:Connect(toggle)
	closeBtn.Activated:Connect(function()
		setOpen(false)
	end)

	ContextActionService:BindAction("ToggleLeaderboard", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			toggle()
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.T)
end

return LeaderboardUI
