-- Options window: the gear button next to the Inventory button (top-right)
-- toggles a real settings window (§6.1 panel treatment: title bar, close
-- button, drop shadow). Values live in PlayerSettings (pushed to the
-- server, persisted with the profile).
--
-- Settings are declared in the SETTINGS schema below — a list of sections,
-- each with typed entries — and the window renders itself from it. To add
-- an option: add its key to PlayerSettings.DEFAULTS (+ the server
-- whitelist) and one entry here.
--
-- Current options:
--   * Interface / Trait rail — Compact (icon + name rows) / Minimal
--     (icon-only column), the SpellTrackerUI rail layouts. Rail only: the
--     inventory's traits column is always compact.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local PlayerSettings = require(script.Parent.PlayerSettings)
local Theme = require(script.Parent.Theme)
local TopRightMenu = require(script.Parent.TopRightMenu)
local UIKit = require(script.Parent.UIKit)
local Sfx = require(script.Parent.Sfx)

local player = Players.LocalPlayer

local SettingsUI = {}

local PANEL_W = 400
local PAD = 14 -- window inner padding
local ROW_H = 30
local CHOICE_W = 86 -- one segmented-choice button

-- What the window shows, in order. Entry types: "choice" (mutually-
-- exclusive segmented buttons over a PlayerSettings key).
local SETTINGS = {
	{
		section = "Interface",
		entries = {
			{
				type = "choice",
				key = "traitTracker",
				label = "Trait rail",
				options = {
					{ label = "Compact", value = "compact" },
					{ label = "Minimal", value = "minimal" },
				},
			},
		},
	},
}

-- One segmented-choice row: setting label left, one button per option
-- right-aligned; the selected option reads ember, the rest stone.
local function buildChoiceRow(content, order, entry)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, ROW_H)
	row.BackgroundTransparency = 1
	row.LayoutOrder = order
	row.ZIndex = content.ZIndex
	row.Parent = content

	local groupW = #entry.options * CHOICE_W + (#entry.options - 1) * 4

	local label = UIKit.label(row, entry.label, Theme.Text.Body)
	label.Size = UDim2.new(1, -(groupW + 10), 1, 0)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.ZIndex = row.ZIndex

	local buttons = {}
	local function refresh()
		local current = PlayerSettings.get(entry.key)
		for value, widgets in pairs(buttons) do
			local selected = value == current
			widgets.button.BackgroundColor3 = selected and Theme.Color.Ember500 or Theme.Color.Ink650
			widgets.button.TextColor3 = selected and Color3.fromRGB(255, 228, 200) or Theme.Semantic.TextMuted
			widgets.stroke.Color = selected and Theme.Color.Ember400 or Theme.Semantic.BorderDivider
		end
	end

	for index, option in ipairs(entry.options) do
		local button = Instance.new("TextButton")
		button.Size = UDim2.new(0, CHOICE_W, 1, -4)
		button.AnchorPoint = Vector2.new(1, 0.5)
		button.Position = UDim2.new(1, -(#entry.options - index) * (CHOICE_W + 4), 0.5, 0)
		button.BackgroundColor3 = Theme.Color.Ink650
		button.BorderSizePixel = 0
		button.AutoButtonColor = false
		button.FontFace = Theme.Font.BodyBold
		button.TextSize = Theme.Text.Sm
		button.Text = option.label
		button.ZIndex = row.ZIndex
		button.Parent = row

		local stroke = Instance.new("UIStroke")
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border -- TextButton
		stroke.Thickness = 1
		stroke.Color = Theme.Semantic.BorderDivider
		stroke.Parent = button

		-- Selection-aware hover (UIKit.hover would restore the unselected
		-- tint onto a selected button).
		button.MouseEnter:Connect(function()
			if PlayerSettings.get(entry.key) ~= option.value then
				TweenService:Create(button, Theme.Tween.Fast, { BackgroundColor3 = Theme.Color.Ink600 }):Play()
			end
		end)
		button.MouseLeave:Connect(refresh)

		button.Activated:Connect(function()
			PlayerSettings.set(entry.key, option.value)
		end)
		buttons[option.value] = { button = button, stroke = stroke }
	end

	PlayerSettings.changed:Connect(function(key)
		if key == entry.key then
			refresh()
		end
	end)
	refresh()
end

local ROW_BUILDERS = {
	choice = buildChoiceRow,
}

function SettingsUI.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "SettingsUI"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 40 -- above the big windows, below tooltips (50)
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Gear button, hanging left of the top-right stack's first row.
	local openBtn = TopRightMenu.addAside("⚙")
	openBtn.TextSize = 18

	local panel = Instance.new("Frame")
	panel.Size = UDim2.new(0, PANEL_W, 0, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.new(0.5, 0, 0.4, 0)
	panel.Visible = false
	panel.ZIndex = 2
	panel.Parent = gui
	UIKit.stylePanel(panel)
	UIKit.addShadow(panel)
	UIKit.autoScale(panel) -- centered: grows in place (§9)

	UIKit.titleBar(panel, "Options")
	local closeBtn = UIKit.closeButton(panel)
	closeBtn.Position = UDim2.new(1, -5, 0, 5)
	closeBtn.AnchorPoint = Vector2.new(1, 0)

	-- Rows flow below the title bar; the window height follows them.
	local content = Instance.new("Frame")
	content.Position = UDim2.new(0, PAD, 0, 36 + 8)
	content.Size = UDim2.new(1, -PAD * 2, 0, 0)
	content.AutomaticSize = Enum.AutomaticSize.Y
	content.BackgroundTransparency = 1
	content.ZIndex = panel.ZIndex + 1
	content.Parent = panel

	local bottomPad = Instance.new("UIPadding")
	bottomPad.PaddingBottom = UDim.new(0, PAD)
	bottomPad.Parent = content

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)
	layout.Parent = content

	local order = 0
	for _, section in ipairs(SETTINGS) do
		order += 1
		local header = UIKit.sectionLabel(content, section.section)
		header.Size = UDim2.new(1, 0, 0, 16)
		header.TextXAlignment = Enum.TextXAlignment.Left
		header.LayoutOrder = order

		for _, entry in ipairs(section.entries) do
			order += 1
			ROW_BUILDERS[entry.type](content, order, entry)
		end
	end

	openBtn.Activated:Connect(function()
		panel.Visible = not panel.Visible
		Sfx.play(panel.Visible and "panelOpen" or "panelClose")
	end)
	closeBtn.Activated:Connect(function()
		panel.Visible = false
		Sfx.play("panelClose")
	end)
end

return SettingsUI
