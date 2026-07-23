--[[
	FAMANA Marker Brush — Studio plugin for painting map markers onto the
	hand-sculpted terrain. Click to place, drag to paint with spacing,
	scatter mode for forests, Erase mode to remove. Markers follow the
	MapMarkers convention: a part tagged "<Prefix>_<key>" (Node_tree,
	Enemy_goblin, Border_south, ...) whose CFrame is the placement; they're
	consumed and destroyed at boot, so anything visual here is edit-only.
	Parts go under Workspace.Map.Markers so the map pull carries them.

	INSTALL: copy this file into your local Studio plugins folder
	(Studio -> PLUGINS tab -> Plugins Folder), or let the repo script do it —
	the source of truth is roblox/plugins/ in the repo.
]]

if not plugin then
	return
end

local CollectionService = game:GetService("CollectionService")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local PRESETS = {
	"Node_tree", "Node_conifer_tree", "Node_dead_tree", "Node_hardwood_tree",
	"Node_stone_rock", "Node_copper_rock", "Node_iron_rock",
	"Enemy_slime", "Enemy_goblin",
	"Border_north", "Border_south", "Border_east", "Border_west",
}

local PREFIX_COLORS = {
	Node = Color3.fromRGB(96, 190, 96),
	Enemy = Color3.fromRGB(214, 84, 84),
	Vendor = Color3.fromRGB(84, 130, 214),
	Workbench = Color3.fromRGB(224, 150, 62),
	ItemStand = Color3.fromRGB(170, 100, 214),
	Border = Color3.fromRGB(80, 200, 220),
}

local state = {
	tag = "Node_tree",
	radius = 12,
	count = 1,
	randomYaw = true,
	erase = false,
}

local toolbar = plugin:CreateToolbar("FAMANA")
local button = toolbar:CreateButton(
	"Marker Brush",
	"Paint map markers (Node_/Enemy_/Border_...) onto the terrain",
	"rbxassetid://6035047377")

local widget = plugin:CreateDockWidgetPluginGui(
	"FamanaMarkerBrush",
	DockWidgetPluginGuiInfo.new(
		Enum.InitialDockState.Float, false, false, 250, 420, 220, 300))
widget.Title = "FAMANA Marker Brush"

-- ------------------------------------------------------------------- ui ---
local BG = Color3.fromRGB(46, 46, 46)
local FG = Color3.fromRGB(220, 220, 220)
local ACCENT = Color3.fromRGB(226, 125, 62)

local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.fromScale(1, 1)
scroll.BackgroundColor3 = BG
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 6
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.CanvasSize = UDim2.new()
scroll.Parent = widget

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 4)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = scroll

local pad = Instance.new("UIPadding")
pad.PaddingLeft = UDim.new(0, 8)
pad.PaddingRight = UDim.new(0, 8)
pad.PaddingTop = UDim.new(0, 8)
pad.Parent = scroll

local order = 0
local function nextOrder()
	order += 1
	return order
end

local function label(text)
	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(1, 0, 0, 18)
	l.BackgroundTransparency = 1
	l.TextColor3 = FG
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Font = Enum.Font.SourceSansBold
	l.TextSize = 14
	l.Text = text
	l.LayoutOrder = nextOrder()
	l.Parent = scroll
	return l
end

local function makeButton(text)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(1, 0, 0, 24)
	b.BackgroundColor3 = Color3.fromRGB(62, 62, 62)
	b.BorderSizePixel = 0
	b.TextColor3 = FG
	b.Font = Enum.Font.SourceSans
	b.TextSize = 14
	b.Text = text
	b.LayoutOrder = nextOrder()
	b.Parent = scroll
	return b
end

local function makeTextBox(text)
	local t = Instance.new("TextBox")
	t.Size = UDim2.new(1, 0, 0, 24)
	t.BackgroundColor3 = Color3.fromRGB(34, 34, 34)
	t.BorderSizePixel = 0
	t.TextColor3 = FG
	t.Font = Enum.Font.SourceSans
	t.TextSize = 14
	t.ClearTextOnFocus = false
	t.Text = text
	t.LayoutOrder = nextOrder()
	t.Parent = scroll
	return t
end

label("Marker tag")
local tagBox = makeTextBox(state.tag)
label("Presets")
local presetButtons = {}
local function refreshPresetHighlight()
	for tag, b in pairs(presetButtons) do
		b.BackgroundColor3 = tag == state.tag
			and ACCENT or Color3.fromRGB(62, 62, 62)
	end
end
for _, tag in ipairs(PRESETS) do
	local b = makeButton(tag)
	presetButtons[tag] = b
	b.MouseButton1Click:Connect(function()
		state.tag = tag
		tagBox.Text = tag
		refreshPresetHighlight()
	end)
end
tagBox.FocusLost:Connect(function()
	state.tag = tagBox.Text:gsub("%s", "")
	refreshPresetHighlight()
end)

label("Scatter: count per click / radius (studs)")
local countBox = makeTextBox("1")
local radiusBox = makeTextBox("12")
countBox.FocusLost:Connect(function()
	state.count = math.clamp(tonumber(countBox.Text) or 1, 1, 50)
	countBox.Text = tostring(state.count)
end)
radiusBox.FocusLost:Connect(function()
	state.radius = math.clamp(tonumber(radiusBox.Text) or 12, 2, 100)
	radiusBox.Text = tostring(state.radius)
end)

local yawButton = makeButton("Random yaw: ON")
yawButton.MouseButton1Click:Connect(function()
	state.randomYaw = not state.randomYaw
	yawButton.Text = "Random yaw: " .. (state.randomYaw and "ON" or "OFF")
end)

local eraseButton = makeButton("Mode: PLACE")
eraseButton.MouseButton1Click:Connect(function()
	state.erase = not state.erase
	eraseButton.Text = state.erase and "Mode: ERASE" or "Mode: PLACE"
	eraseButton.BackgroundColor3 = state.erase
		and Color3.fromRGB(160, 60, 60) or Color3.fromRGB(62, 62, 62)
end)

label("Click = place/erase. Drag = paint with")
label("spacing. Border_ tags place wall-sized parts.")
refreshPresetHighlight()

-- ------------------------------------------------------------ placement ---
local function markersFolder(create)
	local map = workspace:FindFirstChild("Map")
	if not map then
		if not create then
			return nil
		end
		map = Instance.new("Folder")
		map.Name = "Map"
		map.Parent = workspace
	end
	local folder = map:FindFirstChild("Markers")
	if not folder and create then
		folder = Instance.new("Folder")
		folder.Name = "Markers"
		folder.Parent = map
	end
	return folder
end

local function raycastGround(origin, direction)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude = {}
	local folder = markersFolder(false)
	if folder then
		table.insert(exclude, folder)
	end
	params.FilterDescendantsInstances = exclude
	return workspace:Raycast(origin, direction, params)
end

local function colorFor(tag)
	local prefix = tag:match("^(%a+)_")
	return PREFIX_COLORS[prefix] or Color3.fromRGB(220, 200, 90)
end

local function placeMarker(position, tag)
	local part = Instance.new("Part")
	part.Name = tag
	part.Anchored = true
	part.CanCollide = false
	part.CastShadow = false
	part.Transparency = 0.4
	part.Color = colorFor(tag)
	if tag:match("^Border_") then
		-- Border markers: position AND size become the crossing trigger
		-- wall (BorderService) — start wall-sized, then move/scale by hand.
		part.Size = Vector3.new(2, 30, 90)
		part.CFrame = CFrame.new(position + Vector3.new(0, 15, 0))
	else
		part.Size = Vector3.new(2, 2, 2)
		local yaw = state.randomYaw and math.rad(math.random() * 360) or 0
		part.CFrame = CFrame.new(position + Vector3.new(0, 1, 0))
			* CFrame.Angles(0, yaw, 0)
	end
	CollectionService:AddTag(part, tag)

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(0, 120, 0, 16)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
	gui.AlwaysOnTop = true
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.TextColor3 = part.Color
	text.TextStrokeTransparency = 0.4
	text.Font = Enum.Font.SourceSansBold
	text.TextSize = 12
	text.Text = tag
	text.Parent = gui
	gui.Parent = part

	part.Parent = markersFolder(true)
end

local function applyAt(hitPos)
	local recording = ChangeHistoryService:TryBeginRecording(
		"FamanaMarkerBrush", state.erase and "Erase markers" or "Place markers")
	if state.erase then
		local folder = markersFolder(false)
		if folder then
			for _, part in ipairs(folder:GetChildren()) do
				if part:IsA("BasePart")
					and (part.Position - hitPos).Magnitude <= state.radius then
					part:Destroy()
				end
			end
		end
	else
		for i = 1, state.count do
			local target = hitPos
			if state.count > 1 or i > 1 then
				local a = math.random() * 2 * math.pi
				local r = math.sqrt(math.random()) * state.radius
				local probe = raycastGround(
					hitPos + Vector3.new(math.cos(a) * r, 200, math.sin(a) * r),
					Vector3.new(0, -600, 0))
				if not probe then
					continue
				end
				target = probe.Position
			end
			placeMarker(target, state.tag)
		end
	end
	if recording then
		ChangeHistoryService:FinishRecording(
			recording, Enum.FinishRecordingOperation.Commit)
	end
end

-- --------------------------------------------------------------- activate ---
local mouse
local connections = {}
local dragging = false
local lastApply

local function hitFromMouse()
	local ray = mouse.UnitRay
	local result = raycastGround(ray.Origin, ray.Direction * 10000)
	return result and result.Position or nil
end

local function enable()
	plugin:Activate(true)
	mouse = plugin:GetMouse()
	table.insert(connections, mouse.Button1Down:Connect(function()
		local hit = hitFromMouse()
		if hit then
			dragging = true
			lastApply = hit
			applyAt(hit)
		end
	end))
	table.insert(connections, mouse.Button1Up:Connect(function()
		dragging = false
	end))
	table.insert(connections, mouse.Move:Connect(function()
		if not dragging then
			return
		end
		local hit = hitFromMouse()
		local spacing = math.max(state.radius, 4)
		if hit and lastApply and (hit - lastApply).Magnitude >= spacing then
			lastApply = hit
			applyAt(hit)
		end
	end))
end

local function disable()
	dragging = false
	for _, c in ipairs(connections) do
		c:Disconnect()
	end
	table.clear(connections)
end

button.Click:Connect(function()
	widget.Enabled = not widget.Enabled
	button:SetActive(widget.Enabled)
	if widget.Enabled then
		enable()
	else
		disable()
	end
end)

plugin.Deactivation:Connect(function()
	-- another tool took over the mouse — keep the widget, stop painting
	disable()
end)

widget:GetPropertyChangedSignal("Enabled"):Connect(function()
	if not widget.Enabled then
		disable()
		button:SetActive(false)
	end
end)
