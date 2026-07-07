-- Options menu: the gear button next to the Inventory button (top-right)
-- opens a small panel of player preferences. Values live in PlayerSettings
-- (pushed to the server, persisted with the profile).
--
-- Current options:
--   * Trait tracker — Compact (icon + name rows) / Minimal (icon-only
--     column), the SpellTrackerUI layouts from docs/traits_*_side.png.

local Players = game:GetService("Players")

local PlayerSettings = require(script.Parent.PlayerSettings)
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)

local player = Players.LocalPlayer

local SettingsUI = {}

-- Aethelgard palette (client/Theme.lua).
local COLORS = {
	tile = Theme.Color.Ink650,
	accent = Theme.Color.Ember500,
	text = Theme.Semantic.TextBody,
	textDim = Theme.Semantic.TextMuted,
}

local PANEL_W = 240

local function makeLabel(parent, text, size, color, font)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.FontFace = font or Theme.Font.BodyBold
	label.TextSize = size
	label.TextColor3 = color or COLORS.text
	label.Text = text
	label.Parent = parent
	return label
end

function SettingsUI.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "SettingsUI"
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Gear button, left of the Inventory (B) button (which sits at 1,-16).
	local openBtn = UIKit.ghostButton(gui, "⚙")
	openBtn.Size = UDim2.new(0, 34, 0, 34)
	openBtn.Position = UDim2.new(1, -142, 0, 16)
	openBtn.AnchorPoint = Vector2.new(1, 0)
	openBtn.TextSize = 18

	local panel = Instance.new("Frame")
	panel.Size = UDim2.new(0, PANEL_W, 0, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	-- Below the Inventory (y 16) and Character (y 56) buttons.
	panel.Position = UDim2.new(1, -16, 0, 96)
	panel.AnchorPoint = Vector2.new(1, 0)
	panel.Visible = false
	panel.ZIndex = 15
	panel.Parent = gui
	UIKit.stylePanel(panel)

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 10)
	pad.PaddingBottom = UDim.new(0, 12)
	pad.PaddingLeft = UDim.new(0, 12)
	pad.PaddingRight = UDim.new(0, 12)
	pad.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = panel

	local title =
		makeLabel(panel, "Options", Theme.Text.Hero, Theme.Semantic.TextTitle, Theme.Font.DisplayBold)
	title.Size = UDim2.new(1, 0, 0, 22)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.LayoutOrder = 1
	title.ZIndex = 16

	-- One choice row: a label over a set of mutually-exclusive buttons.
	-- Extend by calling this again for future settings.
	local function addChoice(order, labelText, settingKey, options)
		local label = makeLabel(panel, string.upper(labelText), Theme.Text.Label, Theme.Semantic.TextLabel)
		label.Size = UDim2.new(1, 0, 0, 16)
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.LayoutOrder = order
		label.ZIndex = 16

		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 28)
		row.BackgroundTransparency = 1
		row.LayoutOrder = order + 1
		row.ZIndex = 16
		row.Parent = panel

		local rowLayout = Instance.new("UIListLayout")
		rowLayout.FillDirection = Enum.FillDirection.Horizontal
		rowLayout.Padding = UDim.new(0, 6)
		rowLayout.Parent = row

		local buttons = {}
		local function refresh()
			local current = PlayerSettings.get(settingKey)
			for value, widgets in pairs(buttons) do
				local selected = value == current
				widgets.button.BackgroundColor3 = selected and COLORS.accent or COLORS.tile
				widgets.button.TextColor3 = selected and Color3.fromRGB(255, 228, 200) or COLORS.textDim
				widgets.stroke.Color = selected and Theme.Color.Ember400 or Theme.Semantic.BorderDivider
			end
		end

		for _, option in ipairs(options) do
			local button = Instance.new("TextButton")
			button.Size = UDim2.new(0, (PANEL_W - 24 - (#options - 1) * 6) / #options, 1, 0)
			button.BackgroundColor3 = COLORS.tile
			button.BorderSizePixel = 0
			button.AutoButtonColor = false
			button.FontFace = Theme.Font.BodyBold
			button.TextSize = 12
			button.Text = option.label
			button.ZIndex = 16
			button.Parent = row

			local stroke = Instance.new("UIStroke")
			stroke.Thickness = 1
			stroke.Color = Theme.Semantic.BorderDivider
			stroke.Parent = button

			button.Activated:Connect(function()
				PlayerSettings.set(settingKey, option.value)
			end)
			buttons[option.value] = { button = button, stroke = stroke }
		end

		PlayerSettings.changed:Connect(function(key)
			if key == settingKey then
				refresh()
			end
		end)
		refresh()
	end

	addChoice(10, "Trait tracker", "traitTracker", {
		{ label = "Compact", value = "compact" },
		{ label = "Minimal", value = "minimal" },
	})

	openBtn.Activated:Connect(function()
		panel.Visible = not panel.Visible
	end)
end

return SettingsUI
