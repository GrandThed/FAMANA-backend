-- Shared Aethelgard widget recipes (docs/UI.md §6) over the Theme tokens:
-- panel shells, title bars, buttons, labels. These style or create plain
-- Instances — no framework, so the existing imperative UIs adopt them
-- piecemeal. Panels/slots stay sharp-cornered by design; only chips and
-- orbs may round.

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Theme = require(script.Parent.Theme)
local Icons = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Icons"))

local UIKit = {}

local S = Theme.Semantic

-- ZIndex of a parent for stacking children above it. ScreenGuis (a common
-- widget parent) have no ZIndex property, so read defensively.
local function baseZ(parent)
	local ok, z = pcall(function()
		return parent.ZIndex
	end)
	return ok and z or 1
end

-- A themed TextLabel. `font` defaults to the bold body serif; pass
-- Theme.Font.Display/DisplayBold for headings.
function UIKit.label(parent, text, size, color, font)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.FontFace = font or Theme.Font.BodyBold
	label.TextSize = size or Theme.Text.Body
	label.TextColor3 = color or S.TextBody
	label.Text = text
	label.Parent = parent
	return label
end

-- Panel shell (§6.1) applied onto an existing Frame: vertical PanelTop→
-- PanelBot gradient, 1px stone border, and the 1px ember "forge light"
-- along the top edge. Returns the UIStroke (callers retint it).
function UIKit.stylePanel(frame)
	frame.BackgroundColor3 = S.PanelTop
	frame.BorderSizePixel = 0

	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(S.PanelTop, S.PanelBot)
	gradient.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1
	stroke.Color = S.BorderPanel
	stroke.Parent = frame

	local forgeLight = Instance.new("Frame")
	forgeLight.Size = UDim2.new(1, 0, 0, 1)
	forgeLight.BackgroundColor3 = Theme.Color.Ember200
	forgeLight.BackgroundTransparency = 0.88
	forgeLight.BorderSizePixel = 0
	forgeLight.ZIndex = frame.ZIndex + 1
	forgeLight.Parent = frame

	return stroke
end

-- Title bar (§6.1): display-serif title over a 2px bottom divider.
-- Returns the title label (the caller parents its own close button).
function UIKit.titleBar(panel, text, height)
	height = height or 36

	local title = UIKit.label(panel, text, Theme.Text.Title, S.TextTitle, Theme.Font.DisplayBold)
	title.Size = UDim2.new(1, -(height + 16), 0, height)
	title.Position = UDim2.new(0, 14, 0, 0)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.ZIndex = panel.ZIndex + 1

	local divider = Instance.new("Frame")
	divider.Size = UDim2.new(1, 0, 0, 2)
	divider.Position = UDim2.new(0, 0, 0, height - 2)
	divider.BackgroundColor3 = S.BorderPanel
	divider.BorderSizePixel = 0
	divider.ZIndex = panel.ZIndex + 1
	divider.Parent = panel

	return title
end

-- Close button (§6.6): small blood-red square with a ✕. Bright glyph and
-- border — the pure token ramp (Blood400 on Blood600) reads as mud in-game.
function UIKit.closeButton(parent, size)
	size = size or 26
	local button = Instance.new("TextButton")
	button.Size = UDim2.new(0, size, 0, size)
	button.BackgroundColor3 = Theme.Color.Blood600
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.FontFace = Theme.Font.BodyBold
	button.TextSize = 15
	button.TextColor3 = Color3.fromRGB(244, 186, 162)
	button.Text = "✕"
	button.ZIndex = baseZ(parent) + 2
	button.Parent = parent

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1
	stroke.Color = Theme.Color.Blood400
	stroke.Transparency = 0.25
	stroke.Parent = button

	UIKit.hover(button, Theme.Color.Blood600, Theme.Color.Blood500)
	return button
end

-- Hover tint helper (§11: fast, no bounce). Also restores on leave.
function UIKit.hover(button, normalColor, hoverColor)
	button.MouseEnter:Connect(function()
		TweenService:Create(button, Theme.Tween.Fast, { BackgroundColor3 = hoverColor }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(button, Theme.Tween.Fast, { BackgroundColor3 = normalColor }):Play()
	end)
end

-- Primary button (§6.6): ember gradient, ember stroke, warm display label.
-- Brighter than the raw token ramp (Ember500→600 renders muddy in-engine;
-- the mock's button pops like Ember400→500).
function UIKit.primaryButton(parent, text)
	local button = Instance.new("TextButton")
	button.BackgroundColor3 = Theme.Color.Ember400
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.FontFace = Theme.Font.DisplayBold
	button.TextSize = Theme.Text.Lg
	button.TextColor3 = Color3.fromRGB(255, 232, 205)
	button.Text = text
	button.ZIndex = baseZ(parent) + 1
	button.Parent = parent

	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(Theme.Color.Ember400, Theme.Color.Ember500)
	gradient.Parent = button

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1
	stroke.Color = Theme.Color.Ember200
	stroke.Transparency = 0.3
	stroke.Parent = button

	UIKit.hover(button, Theme.Color.Ember400, Theme.Color.Ember200)
	return button
end

-- Ghost button (§6.6): transparent, stone border, secondary text.
function UIKit.ghostButton(parent, text)
	local button = Instance.new("TextButton")
	button.BackgroundColor3 = Theme.Color.Ink700
	button.BackgroundTransparency = 0.4
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.FontFace = Theme.Font.BodyBold
	button.TextSize = Theme.Text.Sm
	button.TextColor3 = S.TextSecondary
	button.Text = text
	button.ZIndex = baseZ(parent) + 1
	button.Parent = parent

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1
	stroke.Color = S.BorderDivider
	stroke.Parent = button

	UIKit.hover(button, Theme.Color.Ink700, Theme.Color.Ink650)
	return button
end

-- All-caps section label ("EQUIPMENT", "EFFECTS", …).
function UIKit.sectionLabel(parent, text)
	local label = UIKit.label(parent, string.upper(text), Theme.Text.Label, S.TextLabel)
	label.ZIndex = baseZ(parent) + 1
	return label
end

-- ---- responsiveness (§9) --------------------------------------------------------

local DESIGN = Vector2.new(1280, 720) -- the mock resolution everything is authored at

-- The current viewport→design scale factor. Code that mixes screen-space
-- coordinates (mouse, AbsolutePosition) with design-space offsets inside a
-- scaled element multiplies/divides by this.
function UIKit.scaleFactor()
	local camera = Workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or DESIGN
	return math.clamp(math.min(viewport.X / DESIGN.X, viewport.Y / DESIGN.Y), 0.65, 1.4)
end

-- Fits a top-level GuiObject to the viewport with a UIScale. Scaling happens
-- around the object's own AnchorPoint, so corner-pinned HUD chrome stays
-- pinned and centered windows grow in place. The object's own Position is
-- untouched (screen-space); its Size and descendants scale.
function UIKit.autoScale(guiObject)
	local scale = Instance.new("UIScale")
	scale.Scale = UIKit.scaleFactor()
	scale.Parent = guiObject

	local camera = Workspace.CurrentCamera
	if camera then
		-- Disconnect with the host (short-lived popups create these too).
		local connection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			scale.Scale = UIKit.scaleFactor()
		end)
		scale.Destroying:Connect(function()
			connection:Disconnect()
		end)
	end
	return scale
end

-- ---- asset-backed effects (shared/Icons) ------------------------------------------

-- Inner radial glow (rarity emphasis, §6.2): an ImageLabel filling `parent`,
-- tinted `color`. Returns nil while the RadialGlow asset id isn't uploaded —
-- callers must tolerate that.
function UIKit.addGlow(parent, color, transparency)
	local image = Icons.image("RadialGlow")
	if not image then
		return nil
	end
	local glow = Instance.new("ImageLabel")
	glow.Name = "Glow"
	glow.Size = UDim2.new(1, 0, 1, 0)
	glow.BackgroundTransparency = 1
	glow.Image = image
	glow.ImageColor3 = color or Color3.new(1, 1, 1)
	glow.ImageTransparency = transparency or 0.72
	glow.ZIndex = baseZ(parent)
	glow.Parent = parent
	return glow
end

-- 9-slice drop shadow behind a fixed-size frame (§6.1). Children always draw
-- above their parent (Sibling ZIndex), so the shadow is a SIBLING that
-- mirrors the frame's geometry — including through slide tweens. Skip for
-- AutomaticSize frames (their Size property never changes). Returns nil
-- while the Shadow9Slice asset id isn't uploaded.
function UIKit.addShadow(frame, spread)
	local image = Icons.image("Shadow9Slice")
	if not image then
		return nil
	end
	spread = spread or 20

	local shadow = Instance.new("ImageLabel")
	shadow.Name = frame.Name .. "Shadow"
	shadow.BackgroundTransparency = 1
	shadow.Image = image
	shadow.ScaleType = Enum.ScaleType.Slice
	shadow.SliceCenter = Rect.new(48, 48, 80, 80)
	-- The asset is white-on-transparent like the rest of the icon set —
	-- tint it black or it reads as a pale halo instead of a shadow.
	shadow.ImageColor3 = Color3.new(0, 0, 0)
	shadow.ImageTransparency = 0.25
	shadow.ZIndex = math.max(baseZ(frame) - 1, 0)

	local function sync()
		local anchor = frame.AnchorPoint
		shadow.AnchorPoint = anchor
		shadow.Size = UDim2.new(
			frame.Size.X.Scale,
			frame.Size.X.Offset + spread * 2,
			frame.Size.Y.Scale,
			frame.Size.Y.Offset + spread * 2
		)
		-- Keeps the enlarged box centered on the frame for any AnchorPoint.
		shadow.Position = UDim2.new(
			frame.Position.X.Scale,
			frame.Position.X.Offset + spread * (2 * anchor.X - 1),
			frame.Position.Y.Scale,
			frame.Position.Y.Offset + spread * (2 * anchor.Y - 1)
		)
		shadow.Visible = frame.Visible
	end
	frame:GetPropertyChangedSignal("Position"):Connect(sync)
	frame:GetPropertyChangedSignal("Size"):Connect(sync)
	frame:GetPropertyChangedSignal("Visible"):Connect(sync)
	sync()
	shadow.Parent = frame.Parent
	return shadow
end

return UIKit
