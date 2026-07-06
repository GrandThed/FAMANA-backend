-- TFT-style subclass tracker: a vertical strip on the left edge listing every
-- school (subclass) of the current class, with the class level against the
-- next unlock threshold ("7/10", like TFT's trait counts). Hovering an entry
-- opens a tooltip with the school's whole level timeline (spells + passive
-- per threshold, reached tiers bright / future ones gray) and its spell
-- list — hover a spell row and press 3–0 to bind it to that hotbar key on
-- the active page. The mouse is never locked in this game, so this works
-- mid-play; ClientState.spellHover stops HudUI from also casting on the
-- same keypress.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Spells = require(Shared:WaitForChild("Spells"))
local HotbarBinds = require(script.Parent.HotbarBinds)
local SpellsClient = require(script.Parent.SpellsClient)
local ClientState = require(script.Parent.ClientState)

local player = Players.LocalPlayer

local SpellTrackerUI = {}

local PANEL_X = 10
local ENTRY_W, ENTRY_H = 158, 36
local TOOLTIP_W = 260

local COLORS = {
	panel = Color3.fromRGB(20, 20, 26),
	line = Color3.fromRGB(60, 60, 72),
	text = Color3.fromRGB(235, 235, 240),
	textDim = Color3.fromRGB(140, 140, 152),
	gold = Color3.fromRGB(255, 220, 120),
	rowHover = Color3.fromRGB(45, 45, 56),
}

-- Bind keys 3..0 → hotbar slot index 2..9 (same map as InventoryUI).
local BIND_KEYS = {
	[Enum.KeyCode.Three] = 2,
	[Enum.KeyCode.Four] = 3,
	[Enum.KeyCode.Five] = 4,
	[Enum.KeyCode.Six] = 5,
	[Enum.KeyCode.Seven] = 6,
	[Enum.KeyCode.Eight] = 7,
	[Enum.KeyCode.Nine] = 8,
	[Enum.KeyCode.Zero] = 9,
}

function SpellTrackerUI.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "SpellTrackerUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true -- offsets match AbsolutePosition (like HudUI)
	gui.Parent = player:WaitForChild("PlayerGui")

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0, 0.5)
	panel.Position = UDim2.new(0, PANEL_X, 0.42, 0)
	panel.Size = UDim2.new(0, ENTRY_W, 0, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.BackgroundTransparency = 1
	panel.Parent = gui

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 5)
	layout.Parent = panel

	local tooltip = Instance.new("Frame")
	tooltip.Size = UDim2.new(0, TOOLTIP_W, 0, 100)
	tooltip.BackgroundColor3 = COLORS.panel
	tooltip.BackgroundTransparency = 0.04
	tooltip.BorderSizePixel = 0
	tooltip.Visible = false
	tooltip.ZIndex = 30
	tooltip.Parent = gui

	local tooltipCorner = Instance.new("UICorner")
	tooltipCorner.CornerRadius = UDim.new(0, 6)
	tooltipCorner.Parent = tooltip

	local tooltipStroke = Instance.new("UIStroke")
	tooltipStroke.Thickness = 1.5
	tooltipStroke.Color = COLORS.line
	tooltipStroke.Parent = tooltip

	-- ---- state ----
	local entries = {} -- [schoolId] = { frame, count, school }
	local currentSchool, currentAnchor -- school shown in the tooltip + its entry
	local hoveredSpellId -- spell row under the mouse (known spells only)
	local hideToken = 0

	local function levelNow()
		return player:GetAttribute("Level") or 1
	end

	local function setHoveredSpell(spellId)
		hoveredSpellId = spellId
		ClientState.spellHover = spellId ~= nil
	end

	-- The hotbar key a spell is bound to on the ACTIVE page, or nil.
	local function bindKeyFor(spellId)
		local bind = Spells.toBind(spellId)
		for slot = 2, 9 do
			if HotbarBinds.get(slot) == bind then
				return tostring((slot + 1) % 10)
			end
		end
		return nil
	end

	-- Tooltip disappears shortly after the mouse leaves both the entry and
	-- the tooltip itself (the grace period lets you travel between them).
	local function cancelHide()
		hideToken += 1
	end
	local function scheduleHide()
		hideToken += 1
		local token = hideToken
		task.delay(0.15, function()
			if token == hideToken then
				tooltip.Visible = false
				currentSchool, currentAnchor = nil, nil
				setHoveredSpell(nil)
			end
		end)
	end
	tooltip.MouseEnter:Connect(cancelHide)
	tooltip.MouseLeave:Connect(scheduleHide)

	local function makeTooltipLabel(text, size, color, bold)
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham
		label.TextSize = size
		label.TextColor3 = color
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextTruncate = Enum.TextTruncate.AtEnd
		label.Text = text
		label.ZIndex = 31
		label.Parent = tooltip
		return label
	end

	local function buildTooltip(school, anchorFrame)
		for _, child in ipairs(tooltip:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		setHoveredSpell(nil)

		local level = levelNow()
		local y = 8

		local title = makeTooltipLabel((school.icon or "") .. "  " .. school.name, 16, school.color, true)
		title.Size = UDim2.new(1, -20, 0, 20)
		title.Position = UDim2.new(0, 10, 0, y)
		y += 26

		-- Level timeline: every threshold with what it grants; reached tiers
		-- read bright, future ones gray.
		for _, step in ipairs(Spells.timelineFor(school)) do
			local parts = {}
			for _, spellId in ipairs(step.spells) do
				local def = Spells.get(spellId)
				if def then
					table.insert(parts, (def.icon or "") .. " " .. def.name)
				end
			end
			if step.familiars then
				table.insert(parts, ("%d familiars"):format(step.familiars))
			end
			if step.passive and school.passive then
				table.insert(parts, Spells.passiveLabel(school.passive.stat, step.passive))
			end
			local reached = level >= step.level
			local line = makeTooltipLabel(
				("Lv %d — %s"):format(step.level, table.concat(parts, " · ")),
				12,
				reached and COLORS.text or COLORS.textDim
			)
			line.Size = UDim2.new(1, -20, 0, 15)
			line.Position = UDim2.new(0, 10, 0, y)
			y += 17
		end

		y += 5
		local divider = Instance.new("Frame")
		divider.Size = UDim2.new(1, -20, 0, 1)
		divider.Position = UDim2.new(0, 10, 0, y)
		divider.BackgroundColor3 = COLORS.line
		divider.BorderSizePixel = 0
		divider.ZIndex = 31
		divider.Parent = tooltip
		y += 8

		-- Spell rows: hover one and press 3–0 to bind it to that key.
		for _, grant in ipairs(school.spells) do
			local spellId, unlockLevel = grant[1], grant[2]
			local def = Spells.get(spellId)
			if def then
				local known = SpellsClient.isKnown(spellId)

				local row = Instance.new("TextButton")
				row.Size = UDim2.new(1, -12, 0, 26)
				row.Position = UDim2.new(0, 6, 0, y)
				row.BackgroundColor3 = COLORS.rowHover
				row.BackgroundTransparency = 1
				row.AutoButtonColor = false
				row.BorderSizePixel = 0
				row.Font = Enum.Font.GothamMedium
				row.TextSize = 13
				row.TextColor3 = known and COLORS.text or COLORS.textDim
				row.TextXAlignment = Enum.TextXAlignment.Left
				row.Text = ("   %s  %s"):format(def.icon or "✦", def.name)
				row.ZIndex = 31
				row.Parent = tooltip

				local rowCorner = Instance.new("UICorner")
				rowCorner.CornerRadius = UDim.new(0, 4)
				rowCorner.Parent = row

				local badge = Instance.new("TextLabel")
				badge.Size = UDim2.new(0, 50, 1, 0)
				badge.Position = UDim2.new(1, -56, 0, 0)
				badge.BackgroundTransparency = 1
				badge.Font = Enum.Font.GothamBold
				badge.TextSize = 12
				badge.TextXAlignment = Enum.TextXAlignment.Right
				badge.ZIndex = 32
				badge.Parent = row
				local boundKey = known and bindKeyFor(spellId) or nil
				if boundKey then
					badge.Text = "[" .. boundKey .. "]"
					badge.TextColor3 = COLORS.gold
				elseif not known then
					badge.Text = "Lv " .. unlockLevel
					badge.TextColor3 = COLORS.textDim
				else
					badge.Text = ""
				end

				if known then
					row.MouseEnter:Connect(function()
						cancelHide()
						setHoveredSpell(spellId)
						row.BackgroundTransparency = 0
					end)
					row.MouseLeave:Connect(function()
						if hoveredSpellId == spellId then
							setHoveredSpell(nil)
						end
						row.BackgroundTransparency = 1
					end)
				end

				y += 28
			end
		end

		local hint = makeTooltipLabel("Hover a spell and press 3–0 to bind it", 11, COLORS.textDim)
		hint.Size = UDim2.new(1, -20, 0, 14)
		hint.Position = UDim2.new(0, 10, 0, y + 2)
		y += 20

		tooltip.Size = UDim2.new(0, TOOLTIP_W, 0, y + 6)
		local anchorY = anchorFrame.AbsolutePosition.Y
		local maxY = math.max(8, gui.AbsoluteSize.Y - (y + 14))
		tooltip.Position = UDim2.new(0, PANEL_X + ENTRY_W + 10, 0, math.clamp(anchorY, 8, maxY))
		tooltip.Visible = true
	end

	local function showTooltip(school, anchorFrame)
		cancelHide()
		currentSchool, currentAnchor = school, anchorFrame
		buildTooltip(school, anchorFrame)
	end

	-- Rebuild in place (badges, known states, timeline brightness).
	local function refreshTooltip()
		if tooltip.Visible and currentSchool and currentAnchor then
			buildTooltip(currentSchool, currentAnchor)
		end
	end

	-- ---- tracker entries ----
	local refreshCounts

	local function rebuildEntries()
		for _, entry in pairs(entries) do
			entry.frame:Destroy()
		end
		entries = {}
		tooltip.Visible = false
		currentSchool, currentAnchor = nil, nil
		setHoveredSpell(nil)

		local classId = player:GetAttribute("Class")
		for order, school in ipairs(Spells.schoolsFor(classId)) do
			local frame = Instance.new("TextButton")
			frame.Size = UDim2.new(1, 0, 0, ENTRY_H)
			frame.LayoutOrder = order
			frame.AutoButtonColor = false
			frame.Text = ""
			frame.BackgroundColor3 = COLORS.panel
			frame.BackgroundTransparency = 0.25
			frame.BorderSizePixel = 0
			frame.Parent = panel

			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, 6)
			corner.Parent = frame

			local stroke = Instance.new("UIStroke")
			stroke.Thickness = 1.5
			stroke.Color = school.color
			stroke.Transparency = 0.45
			stroke.Parent = frame

			local icon = Instance.new("TextLabel")
			icon.Size = UDim2.new(0, 26, 0, 26)
			icon.Position = UDim2.new(0, 5, 0.5, -13)
			icon.BackgroundColor3 = school.color
			icon.BackgroundTransparency = 0.65
			icon.BorderSizePixel = 0
			icon.Font = Enum.Font.GothamBold
			icon.TextSize = 15
			icon.Text = school.icon or "✦"
			icon.Parent = frame

			local iconCorner = Instance.new("UICorner")
			iconCorner.CornerRadius = UDim.new(0, 5)
			iconCorner.Parent = icon

			local name = Instance.new("TextLabel")
			name.Size = UDim2.new(1, -84, 1, 0)
			name.Position = UDim2.new(0, 38, 0, 0)
			name.BackgroundTransparency = 1
			name.Font = Enum.Font.GothamBold
			name.TextSize = 13
			name.TextColor3 = COLORS.text
			name.TextXAlignment = Enum.TextXAlignment.Left
			name.Text = school.name
			name.Parent = frame

			local count = Instance.new("TextLabel")
			count.Size = UDim2.new(0, 42, 1, 0)
			count.Position = UDim2.new(1, -48, 0, 0)
			count.BackgroundTransparency = 1
			count.Font = Enum.Font.GothamBold
			count.TextSize = 13
			count.TextXAlignment = Enum.TextXAlignment.Right
			count.Text = ""
			count.Parent = frame

			frame.MouseEnter:Connect(function()
				showTooltip(school, frame)
			end)
			frame.MouseLeave:Connect(scheduleHide)

			entries[school.id] = { frame = frame, count = count, school = school }
		end
		refreshCounts()
	end

	-- "7/10" toward the next threshold; plain gold level once maxed.
	refreshCounts = function()
		local level = levelNow()
		for _, entry in pairs(entries) do
			local nextLevel
			for _, step in ipairs(Spells.timelineFor(entry.school)) do
				if step.level > level then
					nextLevel = step.level
					break
				end
			end
			if nextLevel then
				entry.count.Text = ("%d/%d"):format(level, nextLevel)
				entry.count.TextColor3 = COLORS.textDim
			else
				entry.count.Text = tostring(level)
				entry.count.TextColor3 = COLORS.gold
			end
		end
	end

	-- Hovered spell + 3–0 → bind to that key on the active page. HudUI skips
	-- its cast/equip handling while ClientState.spellHover is set.
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		local slot = BIND_KEYS[input.KeyCode]
		if slot and hoveredSpellId then
			HotbarBinds.set(slot, Spells.toBind(hoveredSpellId))
		end
	end)

	player:GetAttributeChangedSignal("Class"):Connect(rebuildEntries)
	player:GetAttributeChangedSignal("Level"):Connect(function()
		refreshCounts()
		refreshTooltip()
	end)
	SpellsClient.changed:Connect(refreshTooltip)
	HotbarBinds.changed:Connect(refreshTooltip)

	rebuildEntries()
end

return SpellTrackerUI
