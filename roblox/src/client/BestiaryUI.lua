-- Bestiary panel (K key / top-right button): every enemy with known loot
-- data (shared/Bestiary.knownSources), the player's lifetime kill count
-- against it, and its drop table revealed progressively by tier — same
-- reveal rule EnemyInspectUI's scout card uses (shared/Bestiary.lua,
-- docs/BESTIARY.md). Unlike EnemyInspectUI this never needs a live target
-- or a server round-trip: kills (BestiaryClient) and loot tables (Loot) are
-- both already mirrored client-side, so the whole panel renders locally and
-- just re-renders on BestiaryClient.changed.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Items = require(Shared:WaitForChild("Items"))
local Loot = require(Shared:WaitForChild("Loot"))
local Rarity = require(Shared:WaitForChild("Rarity"))
local Bestiary = require(Shared:WaitForChild("Bestiary"))
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)
local TopRightMenu = require(script.Parent.TopRightMenu)
local BestiaryClient = require(script.Parent.BestiaryClient)
local Sfx = require(script.Parent.Sfx)

local player = Players.LocalPlayer

local BestiaryUI = {}

local COLORS = {
	section = Theme.Semantic.SurfaceWell,
	line = Theme.Semantic.BorderHair,
	tile = Theme.Color.Ink900,
	accent = Theme.Color.Ember300,
	text = Theme.Semantic.TextBody,
	textDim = Theme.Semantic.TextMuted,
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

-- itemId's own rarity tier colors its name, same convention as
-- EnemyInspectUI's coloredName.
local function coloredName(itemId, prefix)
	local itemDef = Items.get(itemId)
	local rarity = Rarity.forDef(itemDef)
	return (prefix or "") .. (itemDef and itemDef.name or itemId), rarity.hasGlow and rarity.textColor or nil
end

function BestiaryUI.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "BestiaryUI"
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

	local title = makeLabel(panel, "Bestiary", Theme.Text.Title, Theme.Semantic.TextTitle, Theme.Font.DisplayBold)
	title.Size = UDim2.new(1, -80, 0, 30)
	title.Position = UDim2.new(0, 12, 0, 4)

	local closeBtn = UIKit.closeButton(panel)
	closeBtn.Position = UDim2.new(1, -6, 0, 6)
	closeBtn.AnchorPoint = Vector2.new(1, 0)

	local list = Instance.new("ScrollingFrame")
	list.Size = UDim2.new(1, -24, 1, -52)
	list.Position = UDim2.new(0, 12, 0, 44)
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

	-- One "Label ......... Value" row inside a card, same shape
	-- EnemyInspectUI's addRow uses.
	local function addRow(parent, order)
		local row = Instance.new("Frame")
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, 16)
		row.LayoutOrder = order
		row.Parent = parent

		local label = makeLabel(row, "", 12, COLORS.text)
		label.Size = UDim2.new(0.6, 0, 1, 0)

		local value = makeLabel(row, "", 12, COLORS.text)
		value.Size = UDim2.new(0.4, 0, 1, 0)
		value.Position = UDim2.new(0.6, 0, 0, 0)
		value.TextXAlignment = Enum.TextXAlignment.Right

		return label, value
	end

	local function makeCard(order, source)
		local kills = BestiaryClient.kills(source)
		local tier = Bestiary.tierForKills(kills)
		local toNext = Bestiary.killsToNextTier(kills)

		local card = Instance.new("Frame")
		card.Size = UDim2.new(1, 0, 0, 0)
		card.AutomaticSize = Enum.AutomaticSize.Y
		card.BackgroundColor3 = COLORS.tile
		card.BackgroundTransparency = 0.35
		card.BorderSizePixel = 0
		card.LayoutOrder = order
		card.Parent = list

		local cardStroke = Instance.new("UIStroke")
		cardStroke.Thickness = kills > 0 and 2 or 1
		cardStroke.Color = kills > 0 and COLORS.accent or COLORS.line
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

		local displayName = Bestiary.NAMES[source] or source
		local nameLabel = makeLabel(nameRow, kills > 0 and displayName or "???", 15, COLORS.text, Theme.Font.DisplayBold)
		nameLabel.Size = UDim2.new(1, -140, 1, 0)

		local killsTag = makeLabel(
			nameRow,
			string.format("%d kills · Tier %d/3", kills, tier),
			11,
			kills > 0 and COLORS.accent or COLORS.textDim,
			Theme.Font.BodyBold
		)
		killsTag.Size = UDim2.new(0, 140, 1, 0)
		killsTag.Position = UDim2.new(1, -140, 0, 0)
		killsTag.TextXAlignment = Enum.TextXAlignment.Right

		if kills == 0 then
			-- Never killed: nothing to show at all, not even a locked drop
			-- list — the first kill is what puts this entry on the map.
			local hint = makeLabel(card, "Defeat one to add it to your bestiary.", 12, COLORS.textDim, Theme.Font.BodyItalic)
			hint.Size = UDim2.new(1, 0, 0, 16)
			hint.LayoutOrder = 2
			return
		end

		local statusLabel, statusValue = addRow(card, 2)
		statusLabel.Text = "Next reveal"
		statusValue.Text = toNext and string.format("%d more kills", toNext) or "fully revealed"

		local rowOrder = 3
		local tableLoot = Loot.TABLE[source]
		if tableLoot then
			for _, entry in ipairs(tableLoot) do
				local label, value = addRow(card, rowOrder)
				if Bestiary.isRevealed(entry.tier, kills) then
					local qtyNote = entry.max > 1 and string.format(" x%d-%d", entry.min, entry.max) or ""
					local name, color = coloredName(entry.itemId, nil)
					label.Text = name .. qtyNote
					if color then
						label.TextColor3 = color
					end
					value.Text = string.format("%d%%", math.floor(entry.chance * 100 + 0.5))
				else
					label.Text = "??? "
					label.TextColor3 = COLORS.textDim
					value.Text = "?"
				end
				rowOrder += 1
			end
		end

		local gear = Loot.GEAR[source]
		if gear then
			local gearRevealed = Bestiary.isRevealed(gear.tier, kills)
			local gearLabel, gearValue = addRow(card, rowOrder)
			if gearRevealed then
				gearLabel.Text = "Gear (random)"
				gearValue.Text = string.format("%d%%", math.floor(gear.chance * 100 + 0.5))
			else
				gearLabel.Text = "??? "
				gearLabel.TextColor3 = COLORS.textDim
				gearValue.Text = "?"
			end
			rowOrder += 1
			if gearRevealed then
				for _, itemId in ipairs(gear.pool) do
					local name, color = coloredName(itemId, "  · ")
					local label, value = addRow(card, rowOrder)
					label.Text = name
					label.TextColor3 = color or COLORS.textDim
					value.Text = ""
					rowOrder += 1
				end
			end
		end
	end

	local render
	render = function()
		for _, child in ipairs(list:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local sources = Bestiary.knownSources(Loot)
		for i, source in ipairs(sources) do
			makeCard(i, source)
		end
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

	local openBtn = TopRightMenu.addButton("Bestiary (K)", 7)
	openBtn.Name = "BestiaryButton"
	openBtn.Activated:Connect(toggle)
	closeBtn.Activated:Connect(function()
		setOpen(false)
	end)

	ContextActionService:BindAction("ToggleBestiary", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			toggle()
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.K)

	-- Live refresh while open: a kill against a species currently shown
	-- (or a brand-new species) should update without reopening the panel.
	BestiaryClient.changed:Connect(function()
		if isOpen then
			render()
		end
	end)
end

return BestiaryUI
