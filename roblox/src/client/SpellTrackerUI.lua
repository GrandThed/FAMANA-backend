-- TFT-style tracker. It renders in TWO places at once, one instance each:
--   * an always-on rail hugging the RIGHT screen edge — standalone
--     `SpellTrackerUI.start()` from init.client.lua (right, not left, so it
--     never clashes with the party frames), hover popouts open LEFTWARD;
--   * the traits column inside the inventory panel —
--     `SpellTrackerUI.start(hostFrame)` from InventoryUI, popouts open
--     RIGHTWARD.
-- EVERYTHING here is earned by equipment (the server-set `TraitPoints`
-- attribute — schools and traits alike; the class never feeds points).
-- Two sections in one strip:
--   * SCHOOLS — one entry per school you have points in, points vs next
--     unlock ("3/10"). Hover → tooltip with the whole point timeline
--     (reached tiers bright / future gray) and the spell list; hover a
--     spell row and press 3–0 to bind it to that hotbar key.
--   * TRAITS — one entry per stat trait you have points in, points vs next
--     threshold, lit once the first threshold is active. Hover → tooltip
--     with every threshold's stats.
-- Two layouts, picked in the options menu (SettingsUI → PlayerSettings
-- "traitTracker", docs/traits_*_side.png):
--   * compact — icon + name + count rows (the classic strip)
--   * minimal — a narrow icon-only column with the count underneath
-- The mouse is never locked in this game, so hover-to-bind works mid-play;
-- ClientState.spellHover stops HudUI from also casting on the same keypress.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Spells = require(Shared:WaitForChild("Spells"))
local Traits = require(Shared:WaitForChild("Traits"))
local Icons = require(Shared:WaitForChild("Icons"))
local HotbarBinds = require(script.Parent.HotbarBinds)
local SpellsClient = require(script.Parent.SpellsClient)
local ClientState = require(script.Parent.ClientState)
local PlayerSettings = require(script.Parent.PlayerSettings)
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)

local player = Players.LocalPlayer

local SpellTrackerUI = {}

local PANEL_X = 10 -- rail inset from the right screen edge
local ENTRY_W, ENTRY_H = 158, 36 -- compact rows
local MINIMAL_W, MINIMAL_H = 48, 46 -- minimal (icon-only) entries
local TOOLTIP_W = 260

-- Widest layout mode, in px — InventoryUI reserves a column this wide so
-- switching modes in the options menu never clips.
SpellTrackerUI.MAX_WIDTH = ENTRY_W

-- Aethelgard palette (client/Theme.lua).
local COLORS = {
	panel = Theme.Color.Ink800,
	line = Theme.Semantic.BorderMuted,
	text = Theme.Semantic.TextStrong,
	textDim = Theme.Semantic.TextMuted,
	gold = Theme.Semantic.Currency,
	rowHover = Theme.Color.Ink650,
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

-- With `hostFrame` the tracker mounts inside it (the inventory's traits
-- column — it inherits that panel's UIScale, so no autoScale, and the
-- tooltip hangs off the panel's RIGHT edge). Without it, it builds the
-- always-on rail pinned to the right screen edge at default DisplayOrder
-- (created early in init, so the big windows draw and hit-test above the
-- rail when they overlap it); its tooltip opens LEFTWARD. Either way the
-- tooltip gets its own top-level ScreenGui — it must render above whatever
-- window is open.
function SpellTrackerUI.start(hostFrame)
	local gui = Instance.new("ScreenGui")
	gui.Name = "SpellTrackerTooltip"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true -- offsets match AbsolutePosition (like HudUI)
	gui.DisplayOrder = 50 -- the tooltip overlays any open panel
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Layout mode from the options menu; the panel narrows in minimal.
	local mode = PlayerSettings.get("traitTracker")
	local function panelWidth()
		return mode == "minimal" and MINIMAL_W or ENTRY_W
	end

	local panel = Instance.new("Frame")
	panel.Size = UDim2.new(0, panelWidth(), 0, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.BackgroundTransparency = 1
	if hostFrame then
		panel.Parent = hostFrame
	else
		local railGui = Instance.new("ScreenGui")
		railGui.Name = "SpellTrackerUI"
		railGui.ResetOnSpawn = false
		railGui.IgnoreGuiInset = true
		railGui.Parent = player:WaitForChild("PlayerGui")
		panel.AnchorPoint = Vector2.new(1, 0.5) -- right edge pinned; width changes grow leftward
		panel.Position = UDim2.new(1, -PANEL_X, 0.42, 0)
		panel.Parent = railGui
		UIKit.autoScale(panel) -- right-edge anchored: scales in place (§9)
	end

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 5)
	layout.Parent = panel

	local tooltip = Instance.new("Frame")
	tooltip.Size = UDim2.new(0, TOOLTIP_W, 0, 100)
	tooltip.BackgroundColor3 = Theme.Semantic.PanelTop
	tooltip.BorderSizePixel = 0
	tooltip.Visible = false
	tooltip.ZIndex = 30
	tooltip.Parent = gui
	UIKit.autoScale(tooltip) -- position stays screen-space; content scales

	-- Panel treatment, sharp corners by design. Gradient/stroke are UI
	-- components (not GuiObjects), so the rebuilds that clear the tooltip's
	-- children leave them alone.
	local tooltipGradient = Instance.new("UIGradient")
	tooltipGradient.Rotation = 90
	tooltipGradient.Color = ColorSequence.new(Theme.Semantic.PanelTop, Theme.Semantic.PanelBot)
	tooltipGradient.Parent = tooltip

	local tooltipStroke = Instance.new("UIStroke")
	tooltipStroke.Thickness = 1
	tooltipStroke.Color = Theme.Semantic.BorderPanel
	tooltipStroke.Parent = tooltip

	-- ---- state ----
	local entries = {} -- [schoolId] = { frame, count, school }
	local traitEntries = {} -- [traitId] = { frame, count, stroke }
	local currentSchool, currentTraitId, currentAnchor -- tooltip subject + its entry
	local hoveredSpellId -- spell row under the mouse (known spells only)
	local hideToken = 0

	-- Trait totals from the server ({ [traitId] = points }).
	local function traitTotals()
		local raw = player:GetAttribute("TraitPoints")
		if typeof(raw) ~= "string" or raw == "" then
			return {}
		end
		local ok, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
		return (ok and typeof(decoded) == "table") and decoded or {}
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
				currentSchool, currentTraitId, currentAnchor = nil, nil, nil
				setHoveredSpell(nil)
			end
		end)
	end
	tooltip.MouseEnter:Connect(cancelHide)
	tooltip.MouseLeave:Connect(scheduleHide)

	local function makeTooltipLabel(text, size, color, bold)
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.FontFace = bold and Theme.Font.BodyBold or Theme.Font.Body
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

		local points = tonumber(traitTotals()[school.id]) or 0
		local y = 8

		local title = makeTooltipLabel(
			("%s  %s — %d pts"):format(school.icon or "", school.name, points),
			16,
			school.color,
			true
		)
		title.Size = UDim2.new(1, -20, 0, 20)
		title.Position = UDim2.new(0, 10, 0, y)
		y += 26

		-- Point timeline: every threshold with what it grants; the tiers your
		-- equipment points reach read bright, future ones gray.
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
			local reached = points >= step.level
			local line = makeTooltipLabel(
				("%d — %s"):format(step.level, table.concat(parts, " · ")),
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
				row.FontFace = Theme.Font.Body
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
				badge.FontFace = Theme.Font.BodyBold
				badge.TextSize = 12
				badge.TextXAlignment = Enum.TextXAlignment.Right
				badge.ZIndex = 32
				badge.Parent = row
				local boundKey = known and bindKeyFor(spellId) or nil
				if boundKey then
					badge.Text = "[" .. boundKey .. "]"
					badge.TextColor3 = COLORS.gold
				elseif not known then
					badge.Text = unlockLevel .. " pts"
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
		-- Screen-space placement: rightward off the inventory column, or
		-- leftward off the right-edge rail (rendered width = design px ×
		-- scale, since the tooltip scales around its own top-left anchor).
		local s = UIKit.scaleFactor()
		local anchorY = anchorFrame.AbsolutePosition.Y
		local maxY = math.max(8, gui.AbsoluteSize.Y - (y + 14) * s)
		local tooltipX = hostFrame and (panel.AbsolutePosition.X + panel.AbsoluteSize.X + 10)
			or (panel.AbsolutePosition.X - TOOLTIP_W * s - 10)
		tooltip.Position = UDim2.new(0, tooltipX, 0, math.clamp(anchorY, 8, maxY))
		tooltip.Visible = true
	end

	-- Trait tooltip: description + every threshold with its stats; the tiers
	-- your current points reach read bright, the rest gray.
	local function buildTraitTooltip(traitDef, anchorFrame)
		for _, child in ipairs(tooltip:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		setHoveredSpell(nil)

		local points = traitTotals()[traitDef.id] or 0
		local y = 8

		local title = makeTooltipLabel(
			("%s  %s — %d pts"):format(traitDef.icon or "✦", traitDef.name, points),
			16,
			traitDef.color,
			true
		)
		title.Size = UDim2.new(1, -20, 0, 20)
		title.Position = UDim2.new(0, 10, 0, y)
		y += 24

		local desc = makeTooltipLabel(traitDef.description or "", 11, COLORS.textDim)
		desc.Size = UDim2.new(1, -20, 0, 28)
		desc.Position = UDim2.new(0, 10, 0, y)
		desc.TextWrapped = true
		desc.TextTruncate = Enum.TextTruncate.None
		y += 32

		for _, threshold in ipairs(traitDef.thresholds) do
			local reached = points >= threshold[1]
			local line = makeTooltipLabel(
				("%d — %s"):format(threshold[1], Traits.tierLabel(threshold[2])),
				12,
				reached and COLORS.text or COLORS.textDim
			)
			line.Size = UDim2.new(1, -20, 0, 15)
			line.Position = UDim2.new(0, 10, 0, y)
			y += 17
		end

		tooltip.Size = UDim2.new(0, TOOLTIP_W, 0, y + 8)
		local s = UIKit.scaleFactor()
		local anchorY = anchorFrame.AbsolutePosition.Y
		local maxY = math.max(8, gui.AbsoluteSize.Y - (y + 16) * s)
		local tooltipX = hostFrame and (panel.AbsolutePosition.X + panel.AbsoluteSize.X + 10)
			or (panel.AbsolutePosition.X - TOOLTIP_W * s - 10)
		tooltip.Position = UDim2.new(0, tooltipX, 0, math.clamp(anchorY, 8, maxY))
		tooltip.Visible = true
	end

	local function showTooltip(school, anchorFrame)
		cancelHide()
		currentSchool, currentTraitId, currentAnchor = school, nil, anchorFrame
		buildTooltip(school, anchorFrame)
	end

	local function showTraitTooltip(traitDef, anchorFrame)
		cancelHide()
		currentSchool, currentTraitId, currentAnchor = nil, traitDef.id, anchorFrame
		buildTraitTooltip(traitDef, anchorFrame)
	end

	-- Rebuild in place (badges, known states, timeline/tier brightness).
	local function refreshTooltip()
		if not (tooltip.Visible and currentAnchor) then
			return
		end
		if currentSchool then
			buildTooltip(currentSchool, currentAnchor)
		elseif currentTraitId and Traits.get(currentTraitId) then
			buildTraitTooltip(Traits.get(currentTraitId), currentAnchor)
		end
	end

	-- The 26px badge for an entry: the hexagon badge from docs/UI.md §6.3 —
	-- hex border tinted the METAL TIER (Bronze/Silver/Gold by thresholds
	-- reached, Prismatic rainbow at the cap), dark inset fill (the same
	-- image scaled down), tier-tinted glyph on top. Falls back to the emoji
	-- chip while the Icons.lua ids aren't uploaded.
	local function buildEntryIcon(parent, id, iconText, color, active, tier)
		local glyphImage = Icons.forTrait(id)
		local hexImage = Icons.image("Hexagon")

		if glyphImage and hexImage then
			local badge = Instance.new("Frame")
			badge.Size = UDim2.new(0, 26, 0, 26)
			badge.BackgroundTransparency = 1
			badge.Parent = parent

			local border = Instance.new("ImageLabel")
			border.Size = UDim2.new(1, 0, 1, 0)
			border.BackgroundTransparency = 1
			border.Image = hexImage
			border.ScaleType = Enum.ScaleType.Fit
			border.ImageColor3 = tier.border
			border.Parent = badge
			if tier == Theme.Tier.Prismatic then
				border.ImageColor3 = Color3.new(1, 1, 1)
				local prism = Instance.new("UIGradient")
				prism.Color = Theme.PrismaticSequence
				prism.Parent = border
			end

			local fill = Instance.new("ImageLabel")
			fill.Size = UDim2.new(0.82, 0, 0.82, 0)
			fill.Position = UDim2.new(0.09, 0, 0.09, 0)
			fill.BackgroundTransparency = 1
			fill.Image = hexImage
			fill.ScaleType = Enum.ScaleType.Fit
			fill.ImageColor3 = tier.fill
			fill.Parent = badge

			local glyph = Instance.new("ImageLabel")
			glyph.Size = UDim2.new(0.55, 0, 0.55, 0)
			glyph.Position = UDim2.new(0.225, 0, 0.225, 0)
			glyph.BackgroundTransparency = 1
			glyph.Image = glyphImage
			glyph.ScaleType = Enum.ScaleType.Fit
			glyph.ImageColor3 = tier.icon
			glyph.Parent = badge
			return badge
		end

		local icon = Instance.new("TextLabel")
		icon.Size = UDim2.new(0, 26, 0, 26)
		icon.BackgroundColor3 = color
		icon.BackgroundTransparency = active and 0.6 or 0.85
		icon.BorderSizePixel = 0
		icon.FontFace = Theme.Font.BodyBold
		icon.TextSize = 15
		icon.Text = iconText or "✦"
		icon.Parent = parent

		local iconCorner = Instance.new("UICorner")
		iconCorner.CornerRadius = UDim.new(0, 5)
		iconCorner.Parent = icon
		return icon
	end

	-- ---- tracker entries ----
	-- One entry frame in the current layout mode (sharp corners by design):
	--   compact — [hex] Name        n/next, with a 2px tier edge when active
	--   minimal — hex over the count, no name (hover for everything else)
	-- Returns the frame and the count label (the caller fills the count in).
	local function buildEntryFrame(order, id, iconText, color, name, active, tier)
		local frame = Instance.new("TextButton")
		frame.Size = UDim2.new(1, 0, 0, mode == "minimal" and MINIMAL_H or ENTRY_H)
		frame.LayoutOrder = order
		frame.AutoButtonColor = false
		frame.Text = ""
		frame.BackgroundColor3 = COLORS.panel
		frame.BackgroundTransparency = active and 0.15 or 0.4
		frame.BorderSizePixel = 0
		frame.Parent = panel

		local stroke = Instance.new("UIStroke")
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border -- entry is a TextButton
		stroke.Thickness = 1
		stroke.Color = Theme.Semantic.BorderHair
		stroke.Transparency = 0.2
		stroke.Parent = frame

		-- The mock's left accent: a 2px tier-colored edge on active rows.
		if active and mode ~= "minimal" then
			local edge = Instance.new("Frame")
			edge.Size = UDim2.new(0, 2, 1, 0)
			edge.BackgroundColor3 = tier.border
			edge.BorderSizePixel = 0
			edge.Parent = frame
		end

		local icon = buildEntryIcon(frame, id, iconText, color, active, tier)

		local count = Instance.new("TextLabel")
		count.BackgroundTransparency = 1
		count.FontFace = Theme.Font.BodyBold
		count.Parent = frame

		if mode == "minimal" then
			icon.Position = UDim2.new(0.5, -13, 0, 4)
			count.Size = UDim2.new(1, 0, 0, 14)
			count.Position = UDim2.new(0, 0, 1, -16)
			count.TextSize = 11
			count.TextXAlignment = Enum.TextXAlignment.Center
		else
			icon.Position = UDim2.new(0, 6, 0.5, -13)
			count.Size = UDim2.new(0, 42, 1, 0)
			count.Position = UDim2.new(1, -48, 0, 0)
			count.TextSize = 13
			count.TextXAlignment = Enum.TextXAlignment.Right

			local nameLabel = Instance.new("TextLabel")
			nameLabel.Size = UDim2.new(1, -84, 1, 0)
			nameLabel.Position = UDim2.new(0, 39, 0, 0)
			nameLabel.BackgroundTransparency = 1
			nameLabel.FontFace = Theme.Font.BodyBold
			nameLabel.TextSize = 13
			nameLabel.TextColor3 = active and COLORS.text or COLORS.textDim
			nameLabel.TextXAlignment = Enum.TextXAlignment.Left
			nameLabel.Text = name
			nameLabel.Parent = frame
		end

		return frame, count
	end

	-- Schools appear only once equipment gives them points (like traits —
	-- equipment is the only source), counted points vs next unlock.
	local function rebuildEntries()
		for _, entry in pairs(entries) do
			entry.frame:Destroy()
		end
		entries = {}
		if currentSchool then
			tooltip.Visible = false
			currentSchool, currentAnchor = nil, nil
			setHoveredSpell(nil)
		end

		local totals = traitTotals()
		for order, schoolId in ipairs(Spells.schoolOrder) do
			local points = tonumber(totals[schoolId]) or 0
			if points > 0 then
				local school = Spells.schools[schoolId]

				-- Metal tier from unlock steps reached (Theme.tierFor).
				local steps = Spells.timelineFor(school)
				local reached, nextPoints = 0, nil
				for _, step in ipairs(steps) do
					if points >= step.level then
						reached += 1
					elseif not nextPoints then
						nextPoints = step.level
					end
				end
				local tier = Theme.tierFor(reached, #steps)

				local frame, count =
					buildEntryFrame(order, schoolId, school.icon, school.color, school.name, true, tier)
				if nextPoints then
					count.Text = ("%d/%d"):format(points, nextPoints)
					count.TextColor3 = COLORS.textDim
				else
					count.Text = tostring(points)
					count.TextColor3 = COLORS.gold
				end

				frame.MouseEnter:Connect(function()
					showTooltip(school, frame)
				end)
				frame.MouseLeave:Connect(scheduleHide)

				entries[school.id] = { frame = frame, count = count, school = school }
			end
		end
	end

	-- ---- trait entries (equipment synergies) ----
	-- Only traits with points show up; lit once their first threshold is
	-- active, gray while still building toward it.
	local function rebuildTraitEntries()
		for _, entry in pairs(traitEntries) do
			entry.frame:Destroy()
		end
		traitEntries = {}
		if currentTraitId then
			tooltip.Visible = false
			currentTraitId, currentAnchor = nil, nil
		end

		local totals = traitTotals()
		for order, traitId in ipairs(Traits.order) do
			local points = tonumber(totals[traitId]) or 0
			local traitDef = Traits.get(traitId)
			if points > 0 and traitDef then
				local active = Traits.activeStats(traitId, points) ~= nil

				-- Metal tier from thresholds reached (Theme.tierFor).
				local reached = 0
				for _, threshold in ipairs(traitDef.thresholds) do
					if points >= threshold[1] then
						reached += 1
					end
				end
				local tier = Theme.tierFor(reached, #traitDef.thresholds)

				-- Traits sit below the schools (LayoutOrder offset).
				local frame, count =
					buildEntryFrame(50 + order, traitId, traitDef.icon, traitDef.color, traitDef.name, active, tier)

				local nextPoints = Traits.nextThreshold(traitId, points)
				if nextPoints then
					count.Text = ("%d/%d"):format(points, nextPoints)
					count.TextColor3 = COLORS.textDim
				else
					count.Text = tostring(points)
					count.TextColor3 = COLORS.gold
				end

				frame.MouseEnter:Connect(function()
					showTraitTooltip(traitDef, frame)
				end)
				frame.MouseLeave:Connect(scheduleHide)

				traitEntries[traitId] = { frame = frame, count = count }
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

	-- Everything keys off the equipment-earned points.
	player:GetAttributeChangedSignal("TraitPoints"):Connect(function()
		rebuildEntries()
		rebuildTraitEntries()
		refreshTooltip()
	end)
	SpellsClient.changed:Connect(refreshTooltip)
	HotbarBinds.changed:Connect(refreshTooltip)

	-- Options menu: swap layouts live (the rebuilds pick up `mode`).
	PlayerSettings.changed:Connect(function(key)
		if key == "traitTracker" then
			mode = PlayerSettings.get("traitTracker")
			panel.Size = UDim2.new(0, panelWidth(), 0, 0)
			rebuildEntries()
			rebuildTraitEntries()
		end
	end)

	rebuildEntries()
	rebuildTraitEntries()
end

return SpellTrackerUI
