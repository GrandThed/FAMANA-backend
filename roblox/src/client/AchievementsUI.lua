-- Achievements panel (L key / top-right button): every shared/Achievements
-- entry with a progress bar, gold reward, and a checkmark once unlocked.
-- Same "render entirely client-side" approach as BestiaryUI — everything
-- Achievements.progress needs is already mirrored via AchievementsClient
-- (attributes, no remote round-trip).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Achievements = require(Shared:WaitForChild("Achievements"))
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)
local TopRightMenu = require(script.Parent.TopRightMenu)
local AchievementsClient = require(script.Parent.AchievementsClient)
local Sfx = require(script.Parent.Sfx)

local player = Players.LocalPlayer

local AchievementsUI = {}

local COLORS = {
	section = Theme.Semantic.SurfaceWell,
	line = Theme.Semantic.BorderHair,
	tile = Theme.Color.Ink900,
	accent = Theme.Color.Ember300,
	text = Theme.Semantic.TextBody,
	textDim = Theme.Semantic.TextMuted,
	barBg = Theme.Color.Ink900,
}

local PANEL_W = 460
local PANEL_H = 520

local function makeLabel(parent, text, size, color, font)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.FontFace = font or Theme.Font.Body
	label.TextSize = size
	label.TextColor3 = color or COLORS.text
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = text
	label.Parent = parent
	return label
end

function AchievementsUI.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "AchievementsUI"
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

	local title = makeLabel(panel, "Achievements", Theme.Text.Title, Theme.Semantic.TextTitle, Theme.Font.DisplayBold)
	title.Size = UDim2.new(1, -80, 0, 30)
	title.Position = UDim2.new(0, 12, 0, 4)

	local progressSummary = makeLabel(panel, "", 12, COLORS.textDim)
	progressSummary.Size = UDim2.new(1, -100, 0, 16)
	progressSummary.Position = UDim2.new(0, 12, 0, 30)

	local closeBtn = UIKit.closeButton(panel)
	closeBtn.Position = UDim2.new(1, -6, 0, 6)
	closeBtn.AnchorPoint = Vector2.new(1, 0)

	local list = Instance.new("ScrollingFrame")
	list.Size = UDim2.new(1, -24, 1, -62)
	list.Position = UDim2.new(0, 12, 0, 54)
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
	layout.Padding = UDim.new(0, 6)
	layout.Parent = list

	local listPadding = Instance.new("UIPadding")
	listPadding.PaddingTop = UDim.new(0, 8)
	listPadding.PaddingLeft = UDim.new(0, 8)
	listPadding.PaddingRight = UDim.new(0, 8)
	listPadding.PaddingBottom = UDim.new(0, 8)
	listPadding.Parent = list

	local function makeCard(order, def, stats)
		local unlockedFlag = AchievementsClient.isUnlocked(def.id)
		local progress = Achievements.progress(def.metric, def.target, stats)
		local fraction = math.clamp(progress / def.amount, 0, 1)

		local card = Instance.new("Frame")
		card.Size = UDim2.new(1, 0, 0, 0)
		card.AutomaticSize = Enum.AutomaticSize.Y
		card.BackgroundColor3 = COLORS.tile
		card.BackgroundTransparency = 0.35
		card.BorderSizePixel = 0
		card.LayoutOrder = order
		card.Parent = list

		local cardStroke = Instance.new("UIStroke")
		cardStroke.Thickness = unlockedFlag and 2 or 1
		cardStroke.Color = unlockedFlag and COLORS.accent or COLORS.line
		cardStroke.Parent = card

		local cardPadding = Instance.new("UIPadding")
		cardPadding.PaddingTop = UDim.new(0, 8)
		cardPadding.PaddingLeft = UDim.new(0, 10)
		cardPadding.PaddingRight = UDim.new(0, 10)
		cardPadding.PaddingBottom = UDim.new(0, 8)
		cardPadding.Parent = card

		local cardLayout = Instance.new("UIListLayout")
		cardLayout.SortOrder = Enum.SortOrder.LayoutOrder
		cardLayout.Padding = UDim.new(0, 3)
		cardLayout.Parent = card

		local nameRow = Instance.new("Frame")
		nameRow.Size = UDim2.new(1, 0, 0, 20)
		nameRow.BackgroundTransparency = 1
		nameRow.LayoutOrder = 1
		nameRow.Parent = card

		local nameLabel = makeLabel(
			nameRow,
			(unlockedFlag and "✓ " or "") .. def.name,
			15,
			unlockedFlag and COLORS.accent or COLORS.text,
			Theme.Font.DisplayBold
		)
		nameLabel.Size = UDim2.new(1, -70, 1, 0)

		local rewardTag = makeLabel(
			nameRow,
			def.reward and def.reward.gold and ("+" .. def.reward.gold .. "g") or "",
			12,
			COLORS.textDim,
			Theme.Font.BodyBold
		)
		rewardTag.Size = UDim2.new(0, 70, 1, 0)
		rewardTag.Position = UDim2.new(1, -70, 0, 0)
		rewardTag.TextXAlignment = Enum.TextXAlignment.Right

		local desc = makeLabel(card, def.description, 12, COLORS.textDim)
		desc.Size = UDim2.new(1, 0, 0, 16)
		desc.LayoutOrder = 2

		local barBg = Instance.new("Frame")
		barBg.Size = UDim2.new(1, 0, 0, 8)
		barBg.BackgroundColor3 = COLORS.barBg
		barBg.BorderSizePixel = 0
		barBg.LayoutOrder = 3
		barBg.Parent = card
		local barBgCorner = Instance.new("UICorner")
		barBgCorner.CornerRadius = UDim.new(1, 0)
		barBgCorner.Parent = barBg

		local barFill = Instance.new("Frame")
		barFill.Size = UDim2.new(fraction, 0, 1, 0)
		barFill.BackgroundColor3 = unlockedFlag and COLORS.accent or Theme.Semantic.TextDim
		barFill.BorderSizePixel = 0
		barFill.Parent = barBg
		local barFillCorner = Instance.new("UICorner")
		barFillCorner.CornerRadius = UDim.new(1, 0)
		barFillCorner.Parent = barFill

		local progressLabel = makeLabel(
			card,
			string.format("%d / %d", math.min(progress, def.amount), def.amount),
			11,
			COLORS.textDim
		)
		progressLabel.Size = UDim2.new(1, 0, 0, 14)
		progressLabel.LayoutOrder = 4
	end

	local render
	render = function()
		for _, child in ipairs(list:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local stats = AchievementsClient.stats()
		local unlockedCount = 0
		for i, def in ipairs(Achievements.LIST) do
			makeCard(i, def, stats)
			if AchievementsClient.isUnlocked(def.id) then
				unlockedCount += 1
			end
		end
		progressSummary.Text = string.format("%d / %d unlocked", unlockedCount, #Achievements.LIST)
	end

	local isOpen = false
	local function setOpen(open)
		isOpen = open
		Sfx.play(isOpen and "panelOpen" or "panelClose")
		panel.Visible = isOpen
		if isOpen then
			render()
		end
	end

	local function toggle()
		setOpen(not isOpen)
	end

	local openBtn = TopRightMenu.addButton("Achievements (L)", 8)
	openBtn.Name = "AchievementsButton"
	openBtn.Activated:Connect(toggle)
	closeBtn.Activated:Connect(function()
		setOpen(false)
	end)

	ContextActionService:BindAction("ToggleAchievements", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			toggle()
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.L)

	AchievementsClient.changed:Connect(function()
		if isOpen then
			render()
		end
	end)
end

return AchievementsUI
