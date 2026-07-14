-- Grid inventory screen (toggled with B / the top-right button).
-- Three columns:
--   traits — the equipment-earned school/trait tracker (a second
--            SpellTrackerUI instance; the always-on rail on the right
--            screen edge is the first)
--   left   — equipment paper doll drawn over a live viewport of the player's
--            character (drag an item onto a slot to equip; while dragging,
--            every slot the item could go to lights up) and the active
--            effects panel (icons + countdowns from Effect_* attributes)
--   right  — utilities bar (Sort button, gold readout) over the scrollable
--            10x30 item grid.
-- Items span WxH cells (item def `size`); drag & drop moves them (R rotates
-- while dragging, green/red highlight previews the drop). Hovering an item
-- and pressing Q throws it on the ground (same verb as dragging it out);
-- pressing 3–0 quick-binds tools/consumables to the hotbar (HotbarBinds);
-- bound items show their key as a badge on the tile. Hovering equippable
-- gear shows trait deltas vs the equipped counterpart in the tooltip
-- (ItemTooltip's compareEntry). Shift-click equips into the first FREE
-- accepting slot — never swaps (that's the 1/2 keys' job) — and
-- shift-clicking a paper-doll slot unequips into the first free grid spot.
--
-- Rendering is a diff: tiles are reused (and just repositioned) across
-- updates so item thumbnails aren't rebuilt on every move/sort. Moves apply
-- optimistically — the tile snaps into place immediately and reverts only if
-- the server rejects the placement.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Items = require(Shared:WaitForChild("Items"))
local Traits = require(Shared:WaitForChild("Traits"))
local Rarity = require(Shared:WaitForChild("Rarity"))
local Icons = require(Shared:WaitForChild("Icons"))
local Spells = require(Shared:WaitForChild("Spells"))
local ItemModels = require(Shared:WaitForChild("ItemModels"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Config = require(Shared:WaitForChild("Config"))
local Effects = require(Shared:WaitForChild("Effects"))
local Classes = require(Shared:WaitForChild("Classes"))
local ClientState = require(script.Parent.ClientState)
local HotbarBinds = require(script.Parent.HotbarBinds)
local ItemTooltip = require(script.Parent.ItemTooltip)
local SpellTrackerUI = require(script.Parent.SpellTrackerUI)
local Theme = require(script.Parent.Theme)
local TopRightMenu = require(script.Parent.TopRightMenu)
local UIKit = require(script.Parent.UIKit)
local Sfx = require(script.Parent.Sfx)

local player = Players.LocalPlayer
local mouse = player:GetMouse()

local InventoryUI = {}

local CELL = Theme.Size.Cell -- px per grid cell (the design system's 42px module)
local GRID_W = Config.inventoryGrid.width
local GRID_H = Config.inventoryGrid.height
local VISIBLE_ROWS = 11 -- grid rows shown before scrolling
local EQUIP_SLOT = 54 -- px, paper-doll slot size
local EQUIP_GAP = 12 -- px between slot rows (lets the character show through)
local CLASS_LABEL_H = 24 -- height reserved for the "<Class> Lvl. <N>" header
local CLASS_SWITCH_H = 20 -- height reserved for the "Cambiar clase" button below it
local HEADER_H = CLASS_LABEL_H + CLASS_SWITCH_H
local TOPBAR = 36

-- Aethelgard palette (client/Theme.lua).
local COLORS = {
	panel = Theme.Semantic.PanelTop,
	section = Theme.Semantic.SurfaceWell,
	line = Theme.Semantic.BorderMuted, -- grid/slot lines need to read on Ink850
	tile = Theme.Color.Ink750, -- item wells sit ABOVE the background, not below it
	tileStroke = Theme.Semantic.BorderSlot,
	good = Theme.Semantic.Good,
	bad = Theme.Semantic.Bad,
	gold = Theme.Semantic.Currency,
	text = Theme.Semantic.TextBody,
	textDim = Theme.Semantic.TextMuted,
}

-- Equip keys → equipment container x (weapon = 0, offhand = 1). Pressing 1/2
-- while hovering a weapon/tool in the grid equips it there, swapping the
-- current occupant back into the grid (needs a free spot).
local EQUIP_KEYS = {
	[Enum.KeyCode.One] = 0,
	[Enum.KeyCode.Two] = 1,
}

-- Quick-bind keys → hotbar slot index (slots 0/1 are the reserved weapons).
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

-- Paper-doll arrangement: [slotName] = { column (0 | 1 | 0.5 = centered), row }.
local SLOT_POS = {
	head = { 0.5, 0 },
	weapon = { 0, 1 },
	chest = { 1, 1 },
	offhand = { 0, 2 },
	hands = { 1, 2 },
	ring1 = { 0, 3 },
	legs = { 1, 3 },
	ring2 = { 0, 4 },
	feet = { 1, 4 },
	back = { 0.5, 5 },
}

-- All-caps like the mock's empty slots (HANDS, LEGS, …).
local SLOT_LABEL = {
	head = "HELMET",
	chest = "CHEST",
	hands = "GLOVES",
	legs = "LEGS",
	feet = "BOOTS",
	weapon = "WEAPON",
	offhand = "OFFHAND",
	back = "BACK",
	ring1 = "RING",
	ring2 = "RING",
}

-- slotName → equipment container x (0-based), from the shared canonical order.
local SLOT_INDEX = {}
for i, name in ipairs(Items.EQUIPMENT_SLOTS) do
	SLOT_INDEX[name] = i - 1
end

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

local function makeViewport(parent)
	local thumb = Instance.new("ViewportFrame")
	thumb.Size = UDim2.new(1, -4, 1, -4)
	thumb.Position = UDim2.new(0, 2, 0, 2)
	thumb.BackgroundTransparency = 1
	thumb.Ambient = Color3.fromRGB(180, 180, 190)
	thumb.LightColor = Color3.new(1, 1, 1)
	thumb.Parent = parent
	return thumb
end

-- ---- mini trait badges (grid tiles + equipment slots) --------------------------
-- Tiny tinted hexes along a tile's bottom-left edge — one per trait/school
-- the piece grants, schools first, so the lines read at a glance (numbers
-- live in the tooltip). Rolls carry at most 3 lines (legendary), so 3 hexes
-- always fit even a 1×1 ring tile.
local MAX_TRAIT_BADGES = 3

local function makeBadgeRow(parent, zIndex)
	local badgeRow = Instance.new("Frame")
	badgeRow.Size = UDim2.new(1, -4, 0, 10)
	badgeRow.Position = UDim2.new(0, 2, 1, -12)
	badgeRow.BackgroundTransparency = 1
	badgeRow.ZIndex = zIndex
	badgeRow.Parent = parent

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 2)
	layout.Parent = badgeRow
	return badgeRow
end

-- Rebuilds a badge row for an entry (the roll rides the ENTRY, not the item
-- id, so this runs per update). Pass nil to just clear it. The UIListLayout
-- survives the clear — it's a UI component, not a GuiObject.
local function fillTraitBadges(badgeRow, entry, def)
	for _, child in ipairs(badgeRow:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local hexImage = Icons.image("Hexagon")
	if not hexImage or not entry then
		return
	end
	local _, entryTraits = Traits.entryInfo(entry, def)
	if typeof(entryTraits) ~= "table" then
		return
	end

	local shown = 0
	local function addBadge(color)
		if shown >= MAX_TRAIT_BADGES then
			return
		end
		shown += 1
		local hex = Instance.new("ImageLabel")
		hex.Size = UDim2.new(0, 9, 0, 10)
		hex.BackgroundTransparency = 1
		hex.Image = hexImage
		hex.ScaleType = Enum.ScaleType.Fit
		hex.ImageColor3 = color
		hex.ZIndex = badgeRow.ZIndex
		hex.Parent = badgeRow
	end
	for _, schoolId in ipairs(Spells.schoolOrder) do
		if entryTraits[schoolId] then
			addBadge(Spells.schools[schoolId].color)
		end
	end
	for _, traitId in ipairs(Traits.order) do
		if entryTraits[traitId] then
			local traitDef = Traits.get(traitId)
			addBadge(traitDef and traitDef.color or Theme.Semantic.TextBody)
		end
	end
end

function InventoryUI.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "InventoryUI"
	gui.ResetOnSpawn = false
	gui.Enabled = true -- always on; we toggle the panel's Visibility instead
	gui.Parent = player:WaitForChild("PlayerGui")

	-- ---- panel shell -------------------------------------------------------
	local gridPixW = GRID_W * CELL
	local rightW = gridPixW + 14 -- room for the scrollbar
	local leftW = 2 * EQUIP_SLOT + 170 -- slot columns at the edges, character between
	local traitsW = SpellTrackerUI.MAX_WIDTH + 20 -- school/trait tracker column
	local panelW = traitsW + leftW + rightW + 48
	local panelH = TOPBAR + VISIBLE_ROWS * CELL + 88
	InventoryUI.panelWidth = panelW -- read by NotificationUI so toasts can dodge the open panel

	-- The panel stays Visible and slides in/out instead of toggling Visible:
	-- its ViewportFrames keep their last paint, so opening doesn't flash
	-- while every thumbnail re-renders on the same frame.
	-- Centered; the chat is moved to the bottom-left instead (ChatConfig).
	local OPEN_POS = UDim2.new(0.5, 0, 0.5, 0)
	local CLOSED_POS = UDim2.new(0.5, 0, 1.7, 0) -- parked below the screen
	local SLIDE_TWEEN = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	local panel = Instance.new("Frame")
	panel.Size = UDim2.new(0, panelW, 0, panelH)
	panel.Position = CLOSED_POS
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Parent = gui
	UIKit.stylePanel(panel) -- gradient + stone border + forge light (§6.1)
	UIKit.addShadow(panel, 24)
	UIKit.autoScale(panel) -- grows in place around its centered anchor (§9)

	local isOpen = false

	UIKit.titleBar(panel, "Inventory", TOPBAR)

	local closeBtn = UIKit.closeButton(panel)
	closeBtn.Position = UDim2.new(1, -5, 0, 5)
	closeBtn.AnchorPoint = Vector2.new(1, 0)

	-- ---- traits column: school/trait tracker (SpellTrackerUI) --------------
	local traitsCol = Instance.new("Frame")
	traitsCol.Size = UDim2.new(0, traitsW, 1, -(TOPBAR + 12))
	traitsCol.Position = UDim2.new(0, 12, 0, TOPBAR)
	traitsCol.BackgroundColor3 = COLORS.section
	traitsCol.BorderSizePixel = 0
	traitsCol.Parent = panel

	local traitsTitle = makeLabel(traitsCol, "TRAITS", Theme.Text.Label, Theme.Semantic.TextLabel)
	traitsTitle.Size = UDim2.new(1, 0, 0, 22)
	traitsTitle.Position = UDim2.new(0, 0, 0, HEADER_H)

	local traitsHost = Instance.new("Frame")
	traitsHost.Size = UDim2.new(1, -20, 1, -(HEADER_H + 26))
	traitsHost.Position = UDim2.new(0, 10, 0, HEADER_H + 24)
	traitsHost.BackgroundTransparency = 1
	traitsHost.Parent = traitsCol

	SpellTrackerUI.start(traitsHost) -- second instance; the right-edge rail is the first

	-- ---- left column: paper doll + effects ---------------------------------
	local leftCol = Instance.new("Frame")
	leftCol.Size = UDim2.new(0, leftW, 1, -(TOPBAR + 12))
	leftCol.Position = UDim2.new(0, traitsW + 24, 0, TOPBAR)
	leftCol.BackgroundColor3 = COLORS.section
	leftCol.BorderSizePixel = 0
	leftCol.Parent = panel

	local equipTitle = makeLabel(leftCol, "EQUIPMENT", Theme.Text.Label, Theme.Semantic.TextLabel)
	equipTitle.Size = UDim2.new(1, 0, 0, 22)
	equipTitle.Position = UDim2.new(0, 0, 0, HEADER_H)

	-- "<Class> Lvl. <N>" above the character, e.g. "Knight Lvl. 5", read
	-- from the server-set "Class"/"Level" attributes.
	local classLabel =
		makeLabel(leftCol, "", Theme.Text.Hero, Theme.Semantic.TextHero, Theme.Font.DisplayBold)
	classLabel.Size = UDim2.new(1, 0, 0, CLASS_LABEL_H)
	classLabel.TextXAlignment = Enum.TextXAlignment.Center

	local classLabelStroke = Instance.new("UIStroke")
	classLabelStroke.Thickness = 1.5
	classLabelStroke.Color = Color3.fromRGB(0, 0, 0)
	classLabelStroke.Transparency = 0.4
	classLabelStroke.Parent = classLabel

	local function refreshClassLabel()
		local level = player:GetAttribute("Level") or 1
		local classDef = Classes.get(player:GetAttribute("Class"))
		classLabel.Text = string.format("%s Lvl. %d", classDef.name, level)
	end
	player:GetAttributeChangedSignal("Level"):Connect(refreshClassLabel)
	player:GetAttributeChangedSignal("Class"):Connect(refreshClassLabel)
	refreshClassLabel()

	-- "Cambiar clase" opens the picker modal (defined further below, once
	-- the top-level `gui` it lives in and the switch remote are in scope).
	local switchClassBtn = UIKit.ghostButton(leftCol, "Cambiar clase")
	switchClassBtn.Size = UDim2.new(1, -16, 0, CLASS_SWITCH_H - 4)
	switchClassBtn.Position = UDim2.new(0, 8, 0, CLASS_LABEL_H)
	switchClassBtn.TextSize = 11

	local equipAreaH = 6 * (EQUIP_SLOT + EQUIP_GAP)

	-- The player's character rendered behind the slots (refreshed on open).
	local dollViewport = Instance.new("ViewportFrame")
	dollViewport.Size = UDim2.new(1, -8, 0, equipAreaH)
	dollViewport.Position = UDim2.new(0, 4, 0, 26 + HEADER_H)
	dollViewport.BackgroundTransparency = 1
	dollViewport.Ambient = Color3.fromRGB(160, 160, 170)
	dollViewport.LightColor = Color3.new(1, 1, 1)
	dollViewport.ZIndex = 1
	dollViewport.Parent = leftCol

	local dollCharacter = nil -- the Character the current doll was cloned from

	local function refreshDoll()
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not character or not root then
			return
		end
		if character == dollCharacter then
			return -- same character instance: the existing clone is still good
		end
		dollCharacter = character
		dollViewport:ClearAllChildren()
		-- Characters aren't Archivable by default; flip it just to clone.
		character.Archivable = true
		local clone = character:Clone()
		character.Archivable = false
		for _, descendant in ipairs(clone:GetDescendants()) do
			if descendant:IsA("BaseScript") or descendant:IsA("Sound") then
				descendant:Destroy()
			elseif descendant:IsA("BasePart") then
				descendant.Anchored = true
			end
		end
		clone:PivotTo(CFrame.new()) -- viewport-local origin
		clone.Parent = dollViewport

		local camera = Instance.new("Camera")
		camera.FieldOfView = 30
		camera.Parent = dollViewport
		dollViewport.CurrentCamera = camera
		local _, size = clone:GetBoundingBox()
		local distance = size.Y * 2.1 + 1
		-- The clone was pivoted to the origin facing -Z; stand in front of it.
		camera.CFrame = CFrame.lookAt(Vector3.new(0, 0.2, -distance), Vector3.new(0, 0, 0))
	end

	-- Slot columns hug the edges so the character reads between them.
	local colX = { [0] = 12, [1] = leftW - EQUIP_SLOT - 12, [0.5] = (leftW - EQUIP_SLOT) / 2 }

	-- equipSlots[slotName] = { frame, thumb, nameLabel, stroke, entry, shownId }
	local equipSlots = {}
	for slotName, pos in pairs(SLOT_POS) do
		local frame = Instance.new("Frame")
		frame.Size = UDim2.new(0, EQUIP_SLOT, 0, EQUIP_SLOT)
		frame.Position = UDim2.new(0, colX[pos[1]], 0, 26 + HEADER_H + pos[2] * (EQUIP_SLOT + EQUIP_GAP))
		frame.BackgroundColor3 = Theme.Color.Ink900 -- slot well (§6.2)
		frame.BackgroundTransparency = 0.3 -- the character shows through a bit
		frame.BorderSizePixel = 0
		frame.ZIndex = 3
		frame.Parent = leftCol

		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 1.5
		stroke.Color = COLORS.line
		stroke.Parent = frame

		local nameLabel =
			makeLabel(frame, SLOT_LABEL[slotName], Theme.Text.Label, Theme.Semantic.TextFaint)
		nameLabel.Size = UDim2.new(1, 0, 1, 0)
		nameLabel.TextWrapped = true
		nameLabel.ZIndex = 4

		local thumb = makeViewport(frame)
		thumb.ZIndex = 4

		-- Red veil for INERT gear: itemLevel above the active class level
		-- (e.g. after switching to a lower-level class) — still equipped,
		-- but contributing nothing until the level allows it again.
		local inertOverlay = Instance.new("Frame")
		inertOverlay.Size = UDim2.new(1, 0, 1, 0)
		inertOverlay.BackgroundColor3 = Theme.Color.Blood500
		inertOverlay.BackgroundTransparency = 0.55
		inertOverlay.BorderSizePixel = 0
		inertOverlay.Visible = false
		inertOverlay.ZIndex = 6
		inertOverlay.Parent = frame

		local inertLabel = makeLabel(frame, "", 10, Theme.Color.Blood400)
		inertLabel.Size = UDim2.new(1, 0, 0, 12)
		inertLabel.Position = UDim2.new(0, 0, 1, -13)
		inertLabel.Visible = false
		inertLabel.ZIndex = 7

		-- Rarity inner glow (uncommon+), retinted per occupant in render.
		local glow = UIKit.addGlow(frame, Color3.new(1, 1, 1), 0.78)
		if glow then
			glow.Visible = false
			glow.ZIndex = 3
		end

		local badgeRow = makeBadgeRow(frame, 5)

		equipSlots[slotName] = {
			frame = frame,
			thumb = thumb,
			nameLabel = nameLabel,
			stroke = stroke,
			glow = glow,
			badgeRow = badgeRow,
			inertOverlay = inertOverlay,
			inertLabel = inertLabel,
			entry = nil,
			shownId = nil,
		}
	end

	local effectsY = 26 + HEADER_H + equipAreaH + 10
	local effectsTitle = makeLabel(leftCol, "EFFECTS", Theme.Text.Label, Theme.Semantic.TextLabel)
	effectsTitle.Size = UDim2.new(1, 0, 0, 22)
	effectsTitle.Position = UDim2.new(0, 0, 0, effectsY)

	local effectsList = Instance.new("Frame")
	effectsList.Size = UDim2.new(1, -20, 1, -(effectsY + 26))
	effectsList.Position = UDim2.new(0, 10, 0, effectsY + 24)
	effectsList.BackgroundTransparency = 1
	effectsList.Parent = leftCol

	local effectsLayout = Instance.new("UIListLayout")
	effectsLayout.Padding = UDim.new(0, 4)
	effectsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	effectsLayout.Parent = effectsList

	-- ---- right column: utilities bar + grid --------------------------------
	local rightX = traitsW + 24 + leftW + 12
	local utilBar = Instance.new("Frame")
	utilBar.Size = UDim2.new(0, rightW, 0, 30)
	utilBar.Position = UDim2.new(0, rightX, 0, TOPBAR)
	utilBar.BackgroundColor3 = COLORS.section
	utilBar.BorderSizePixel = 0
	utilBar.Parent = panel

	local sortBtn = UIKit.primaryButton(utilBar, "Sort")
	sortBtn.Size = UDim2.new(0, 70, 0, 24)
	sortBtn.Position = UDim2.new(0, 4, 0, 3)
	sortBtn.TextSize = Theme.Text.Body

	-- Shows the hovered item's name (poor man's inspect tooltip).
	local hoverLabel = makeLabel(utilBar, "", 13, COLORS.text)
	hoverLabel.Size = UDim2.new(1, -200, 1, 0)
	hoverLabel.Position = UDim2.new(0, 84, 0, 0)
	hoverLabel.TextXAlignment = Enum.TextXAlignment.Left

	local goldLabel = makeLabel(utilBar, "◈ 0 Gold", 14, COLORS.gold)
	goldLabel.Size = UDim2.new(0, 110, 1, 0)
	goldLabel.Position = UDim2.new(1, -114, 0, 0)
	goldLabel.TextXAlignment = Enum.TextXAlignment.Right

	local gridScroll = Instance.new("ScrollingFrame")
	gridScroll.Size = UDim2.new(0, rightW, 0, VISIBLE_ROWS * CELL)
	gridScroll.Position = UDim2.new(0, rightX, 0, TOPBAR + 34)
	gridScroll.BackgroundColor3 = COLORS.section
	gridScroll.BorderSizePixel = 0
	gridScroll.CanvasSize = UDim2.new(0, gridPixW, 0, GRID_H * CELL)
	gridScroll.ScrollBarThickness = 10
	gridScroll.ScrollingDirection = Enum.ScrollingDirection.Y
	gridScroll.Parent = panel

	-- Everything grid-positioned parents here so it scrolls with the canvas.
	local itemsLayer = Instance.new("Frame")
	itemsLayer.Size = UDim2.new(0, gridPixW, 0, GRID_H * CELL)
	itemsLayer.BackgroundTransparency = 1
	itemsLayer.Parent = gridScroll

	-- Grid lines (thin frames beat 300 cell frames).
	for i = 0, GRID_W do
		local line = Instance.new("Frame")
		line.Size = UDim2.new(0, 1, 1, 0)
		line.Position = UDim2.new(0, i * CELL, 0, 0)
		line.BackgroundColor3 = COLORS.line
		line.BorderSizePixel = 0
		line.ZIndex = 1
		line.Parent = itemsLayer
	end
	for j = 0, GRID_H do
		local line = Instance.new("Frame")
		line.Size = UDim2.new(1, 0, 0, 1)
		line.Position = UDim2.new(0, 0, 0, j * CELL)
		line.BackgroundColor3 = COLORS.line
		line.BorderSizePixel = 0
		line.ZIndex = 1
		line.Parent = itemsLayer
	end

	-- Drop preview highlight (green = fits, red = blocked).
	local highlight = Instance.new("Frame")
	highlight.BackgroundColor3 = COLORS.good
	highlight.BackgroundTransparency = 0.6
	highlight.BorderSizePixel = 0
	highlight.Visible = false
	highlight.ZIndex = 5
	highlight.Parent = itemsLayer

	-- ---- state ---------------------------------------------------------------
	local currentInventory = {}
	local hovered = nil -- entry under the mouse (for tooltips/quick binds)
	local drag = nil -- { itemId, from = {containerId,x,y}, rotated, sourceObj, ghost, dropTarget }
	local dragStepConn = nil
	local serverGeneration = 0 -- bumps on every authoritative update (for reverts)

	local moveItemRemote, sortRemote, dropItemRemote, splitStackRemote -- resolved async in the remotes block

	local render -- forward-declared: endDrag (optimistic apply) re-renders

	-- ---- hover tooltip (the §6.5 card, extracted to ItemTooltip and shared
	-- with the store screen). The guard re-checks at fire time that showing
	-- still makes sense here.
	local tooltip = ItemTooltip.create(gui, function()
		return not drag and isOpen
	end)
	local hideTooltip = tooltip.hide
	local scheduleTooltip = tooltip.schedule

	local function sameRef(entry, ref)
		return entry.containerId == ref.containerId and entry.x == ref.x and entry.y == ref.y
	end

	-- Level gate (mirrors PlayerService.moveItem): gear above the active class
	-- level can be carried — and stays equipped-but-INERT through class swaps /
	-- rebirth — but can't be NEWLY equipped. Returns (ok, itemLevel).
	local function equipLevelOk(entry)
		local itemLevel = Traits.entryInfo(entry, Items.get(entry.itemId))
		return itemLevel <= (player:GetAttribute("Level") or 1), itemLevel
	end

	-- Client-side fit preview for the main grid (server still has final say).
	local function canPlace(gx, gy, w, h, itemId)
		if gx < 0 or gy < 0 or gx + w > GRID_W or gy + h > GRID_H then
			return false
		end
		local overlaps = {}
		for _, entry in ipairs(currentInventory) do
			if entry.containerId == "main" and not (drag and sameRef(entry, drag.from)) then
				local ew, eh = Items.sizeFor(entry.itemId, entry.rotated)
				if entry.x < gx + w and gx < entry.x + ew and entry.y < gy + h and gy < entry.y + eh then
					overlaps[#overlaps + 1] = entry
				end
			end
		end
		if #overlaps == 0 then
			return true
		end
		local def = Items.get(itemId)
		if #overlaps == 1 and overlaps[1].itemId == itemId and def and def.stackable then
			return overlaps[1].quantity < Items.maxStackFor(itemId)
		end
		return false
	end

	-- First main-grid position where `itemId` fits (unrotated, then rotated),
	-- judged against the client's current view (the server still validates).
	local function findFreeSpotFor(itemId)
		local w, h = Items.sizeFor(itemId, false)
		local orientations = (w == h) and { false } or { false, true }
		for _, rotated in ipairs(orientations) do
			local tw, th = Items.sizeFor(itemId, rotated)
			for gy = 0, GRID_H - th do
				for gx = 0, GRID_W - tw do
					if canPlace(gx, gy, tw, th, itemId) then
						return { containerId = "main", x = gx, y = gy, rotated = rotated }
					end
				end
			end
		end
		return nil
	end

	-- The entry sitting in an equipment slot (container x), or nil.
	local function occupantAt(slotIndex)
		for _, e in ipairs(currentInventory) do
			if e.containerId == "equipment" and e.x == slotIndex then
				return e
			end
		end
		return nil
	end

	-- The equipped piece a grid item would replace — what the tooltip's
	-- Diablo-style compare card shows: the first accepting slot that holds
	-- something (weapon before offhand, ring1 before ring2).
	local function equippedCounterpart(entry)
		local def = Items.get(entry.itemId)
		if not def or entry.containerId ~= "main" then
			return nil
		end
		for i, slotName in ipairs(Items.EQUIPMENT_SLOTS) do
			if Items.slotAccepts(slotName, def) then
				local occupant = occupantAt(i - 1)
				if occupant then
					return occupant
				end
			end
		end
		return nil
	end

	-- Shift-click equip target: the first accepting EMPTY slot, or nil when
	-- every accepting slot is taken (shift-click never swaps).
	local function shiftEquipSlot(def)
		for i, slotName in ipairs(Items.EQUIPMENT_SLOTS) do
			if Items.slotAccepts(slotName, def) and not occupantAt(i - 1) then
				return i - 1
			end
		end
		return nil
	end

	-- The 1/2 equip shortcut: move the hovered grid item into an equipment
	-- slot. If the slot is taken, the occupant is first unequipped into the
	-- first free grid spot — no free spot, no swap. Two sequential moves; if
	-- the second is rejected the old weapon just ends up unequipped, which is
	-- harmless. Each accepted move already pushes a fresh inventory render.
	local function equipFromGrid(entry, slotIndex)
		if not moveItemRemote then
			return
		end
		local from = { containerId = "main", x = entry.x, y = entry.y }
		local equipRef = { containerId = "equipment", x = slotIndex, y = 0 }

		local occupant = occupantAt(slotIndex)
		if occupant then
			local spot = findFreeSpotFor(occupant.itemId)
			if not spot then
				hoverLabel.Text = "No room to unequip"
				return
			end
			local ok, result = pcall(function()
				return moveItemRemote:InvokeServer(equipRef, spot)
			end)
			if not (ok and typeof(result) == "table" and result.ok == true) then
				return
			end
			Sfx.play("unequip")
		end
		local ok2, result2 = pcall(function()
			return moveItemRemote:InvokeServer(from, equipRef)
		end)
		if ok2 and typeof(result2) == "table" and result2.ok == true then
			Sfx.play("equip")
		end
	end

	-- Occupied slots rest at their item's rarity color, empty ones at the
	-- neutral line (drag flows recolor them green/red on top of this).
	local function resetEquipStrokes()
		for _, slot in pairs(equipSlots) do
			if slot.entry then
				slot.stroke.Color = Rarity.forEntry(slot.entry, Items.get(slot.entry.itemId)).color
			else
				slot.stroke.Color = COLORS.line
			end
			slot.stroke.Thickness = 1.5
		end
	end

	-- While an item is held, every equipment slot it could go to lights up.
	local function markCompatibleSlots()
		if not drag then
			return
		end
		-- Already-equipped pieces may shuffle between slots even when inert.
		local levelOk = drag.from.containerId == "equipment" or (equipLevelOk(drag.entry))
		if not levelOk then
			return
		end
		local def = Items.get(drag.itemId)
		for slotName, slot in pairs(equipSlots) do
			local isSource = slot.entry ~= nil and sameRef(slot.entry, drag.from)
			if Items.slotAccepts(slotName, def) and (slot.entry == nil or isSource) then
				slot.stroke.Color = COLORS.good
				slot.stroke.Thickness = 2
			end
		end
	end

	local function destroyGhost()
		if drag and drag.ghost then
			drag.ghost:Destroy()
		end
	end

	local function buildGhost()
		destroyGhost()
		local w, h = Items.sizeFor(drag.itemId, drag.rotated)
		-- The ghost floats at the unscaled gui level while the panel renders
		-- scaled, so it is sized in screen pixels.
		local s = UIKit.scaleFactor()
		local ghost = Instance.new("Frame")
		ghost.Size = UDim2.new(0, w * CELL * s, 0, h * CELL * s)
		ghost.BackgroundColor3 = COLORS.tile
		ghost.BackgroundTransparency = 0.35
		ghost.BorderSizePixel = 0
		ghost.ZIndex = 50
		ghost.Parent = gui
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2
		stroke.Color = COLORS.gold
		stroke.Parent = ghost
		local thumb = makeViewport(ghost)
		thumb.ZIndex = 51
		ItemModels.preview(thumb, drag.itemId)

		-- Shown when releasing would throw the item on the ground.
		local caption = makeLabel(ghost, "Drop", 12, COLORS.bad)
		caption.Size = UDim2.new(1, 0, 0, 14)
		caption.Position = UDim2.new(0, 0, 1, 2)
		caption.Visible = false
		caption.ZIndex = 51
		drag.ghostCaption = caption

		drag.ghost = ghost
	end

	local function pointIn(guiObject, px, py)
		local pos, size = guiObject.AbsolutePosition, guiObject.AbsoluteSize
		return px >= pos.X and px <= pos.X + size.X and py >= pos.Y and py <= pos.Y + size.Y
	end

	local function updateDrag()
		if not drag then
			return
		end
		local w, h = Items.sizeFor(drag.itemId, drag.rotated)
		-- Screen-space math: the grid renders scaled (autoScale), so one cell
		-- is CELL * scale pixels on screen; the ghost lives unscaled at gui
		-- level. Grid-local coordinates (gx/gy, highlight) stay design px.
		local s = UIKit.scaleFactor()
		local cellPx = CELL * s
		local px = mouse.X - (w * cellPx) / 2
		local py = mouse.Y - (h * cellPx) / 2
		drag.ghost.Position = UDim2.new(0, px, 0, py)

		drag.dropTarget = nil
		highlight.Visible = false
		resetEquipStrokes()
		markCompatibleSlots()

		if pointIn(gridScroll, mouse.X, mouse.Y) then
			local origin = itemsLayer.AbsolutePosition
			local gx = math.floor((px - origin.X) / cellPx + 0.5)
			local gy = math.floor((py - origin.Y) / cellPx + 0.5)
			local ok = canPlace(gx, gy, w, h, drag.itemId)
			highlight.Visible = true
			highlight.Position = UDim2.new(0, math.clamp(gx, 0, GRID_W - 1) * CELL, 0, math.clamp(gy, 0, GRID_H - 1) * CELL)
			highlight.Size = UDim2.new(0, w * CELL, 0, h * CELL)
			highlight.BackgroundColor3 = ok and COLORS.good or COLORS.bad
			if ok then
				drag.dropTarget = { containerId = "main", x = gx, y = gy, rotated = drag.rotated }
			end
		elseif pointIn(panel, mouse.X, mouse.Y) then
			local def = Items.get(drag.itemId)
			for slotName, slot in pairs(equipSlots) do
				if pointIn(slot.frame, mouse.X, mouse.Y) then
					local accepts = Items.slotAccepts(slotName, def)
						and (slot.entry == nil or sameRef(slot.entry, drag.from))
						and (drag.from.containerId == "equipment" or (equipLevelOk(drag.entry)))
					slot.stroke.Color = accepts and COLORS.good or COLORS.bad
					slot.stroke.Thickness = 3
					if accepts then
						drag.dropTarget = { containerId = "equipment", x = SLOT_INDEX[slotName], y = 0 }
					end
					break
				end
			end
		else
			-- Outside the panel entirely: releasing throws the item on the ground.
			drag.dropTarget = { world = true }
		end
		if drag.ghostCaption then
			drag.ghostCaption.Visible = drag.dropTarget ~= nil and drag.dropTarget.world == true
		end
	end

	-- Applies a move to currentInventory locally (position change, equip, or
	-- stack merge — mirrors the backend's rules). Returns a deep snapshot of
	-- the pre-move state for reverting, or nil if the source vanished.
	local function applyOptimisticMove(from, target)
		local snapshot = {}
		for i, entry in ipairs(currentInventory) do
			snapshot[i] = table.clone(entry)
		end

		local source
		for _, entry in ipairs(currentInventory) do
			if sameRef(entry, from) then
				source = entry
				break
			end
		end
		if not source then
			return nil
		end

		if target.containerId == "equipment" then
			source.containerId = "equipment"
			source.x = target.x
			source.y = 0
			source.rotated = false
			return snapshot
		end

		local rotated = target.rotated == true
		local w, h = Items.sizeFor(source.itemId, rotated)
		local def = Items.get(source.itemId)

		-- Dropped onto a same-item stack? Merge locally like the server does.
		if def and def.stackable then
			for index, entry in ipairs(currentInventory) do
				if entry ~= source and entry.containerId == "main" and entry.itemId == source.itemId then
					local ew, eh = Items.sizeFor(entry.itemId, entry.rotated)
					if entry.x < target.x + w and target.x < entry.x + ew
						and entry.y < target.y + h and target.y < entry.y + eh then
						local space = Items.maxStackFor(source.itemId) - entry.quantity
						local transfer = math.min(space, source.quantity)
						entry.quantity += transfer
						source.quantity -= transfer
						if source.quantity <= 0 then
							for i, e in ipairs(currentInventory) do
								if e == source then
									table.remove(currentInventory, i)
									break
								end
							end
						end
						return snapshot
					end
				end
			end
		end

		source.containerId = "main"
		source.x = target.x
		source.y = target.y
		source.rotated = rotated
		return snapshot
	end

	-- Locally removes the stack at `from` (thrown on the ground). Returns a
	-- snapshot for reverting, or nil if the source vanished.
	local function applyOptimisticDrop(from)
		local snapshot = {}
		for i, entry in ipairs(currentInventory) do
			snapshot[i] = table.clone(entry)
		end
		for i, entry in ipairs(currentInventory) do
			if sameRef(entry, from) then
				table.remove(currentInventory, i)
				return snapshot
			end
		end
		return nil
	end

	-- Throws the stack at `from` on the ground — the drag-out verb, shared
	-- with the Q shortcut. Optimistic like moves: remove + render now, ask
	-- the server in the background, revert only on rejection.
	local function throwStack(from)
		local snapshot = applyOptimisticDrop(from)
		if not snapshot then
			return
		end
		render(currentInventory)
		local generationAtMove = serverGeneration
		task.spawn(function()
			local ok, result = false, nil
			if dropItemRemote then
				ok, result = pcall(function()
					return dropItemRemote:InvokeServer(from)
				end)
			end
			local accepted = ok and typeof(result) == "table" and result.ok == true
			if not accepted and serverGeneration == generationAtMove then
				currentInventory = snapshot
				render(snapshot)
			end
		end)
	end

	local function endDrag(commit)
		if not drag then
			return
		end
		local from, target = drag.from, commit and drag.dropTarget or nil
		if dragStepConn then
			dragStepConn:Disconnect()
			dragStepConn = nil
		end
		destroyGhost()
		highlight.Visible = false
		resetEquipStrokes()
		if drag.sourceObj and drag.sourceObj.Parent then
			drag.sourceObj.BackgroundTransparency = drag.sourceTransparency or 0
		end
		drag = nil

		if not target then
			return
		end

		if target.world == true then
			throwStack(from)
			return
		end

		-- Optimistic: apply and show the change now, ask the server in the
		-- background, revert only on rejection (and only if no authoritative
		-- update landed in the meantime).
		local snapshot = applyOptimisticMove(from, target)
		if not snapshot then
			return
		end
		render(currentInventory)

		-- Sonido en el mismo momento que el cambio optimista se ve en
		-- pantalla, no cuando el server confirma (mismo criterio que el
		-- resto de este archivo: se revierte solo si el server rechaza).
		if target.containerId == "equipment" then
			Sfx.play("equip")
		elseif from.containerId == "equipment" then
			Sfx.play("unequip")
		end

		local generationAtMove = serverGeneration

		task.spawn(function()
			local ok, result = false, nil
			if moveItemRemote then
				ok, result = pcall(function()
					return moveItemRemote:InvokeServer(from, target)
				end)
			end
			local accepted = ok and typeof(result) == "table" and result.ok == true
			if not accepted and serverGeneration == generationAtMove then
				currentInventory = snapshot
				render(snapshot)
			end
		end)
	end

	local function beginDrag(entry, fromRef, sourceObj)
		if drag then
			return
		end
		hideTooltip()
		drag = {
			itemId = entry.itemId,
			entry = entry, -- the live entry (meta carries rolled itemLevel)
			from = fromRef,
			rotated = entry.rotated == true,
			sourceObj = sourceObj,
			sourceTransparency = sourceObj.BackgroundTransparency,
		}
		sourceObj.BackgroundTransparency = 0.75
		buildGhost()
		updateDrag()
		dragStepConn = RunService.RenderStepped:Connect(updateDrag)
	end

	-- ---- right-click context menu -------------------------------------------
	-- Right-clicking a grid tile (main container only — equipped items still
	-- use shift-click to unequip) pops a small action list next to the
	-- cursor. Which actions show depends on the item's type:
	--   weapon/tool/armor/ring -> "Usar"     (equip into the first free slot)
	--   placeable              -> "Colocar"  (same equip call — once it's a
	--                                          held Tool, FurniturePlacementUI
	--                                          drives the actual placement)
	--   consumable              -> "Consumir" (no consumable items exist yet,
	--                                          so this never actually renders
	--                                          today; ConsumeItem isn't wired
	--                                          up server-side either — see
	--                                          consumeEntry below)
	--   (anything else, e.g. resource/misc) -> nothing to use
	-- Every type also gets "Soltar" (throw it on the ground).
	local ACTION_LABELS = {
		use = "Usar",
		place = "Colocar",
		consume = "Consumir",
		split = "Dividir",
		drop = "Soltar",
		unequip = "Desequipar",
	}

	local function actionIdsFor(entry, def)
		if entry.containerId == "equipment" then
			return { "unequip" }
		end
		if not def then
			return { "drop" }
		end
		local actions
		if def.type == "weapon" or def.type == "tool" or def.type == "armor" or def.type == "ring" then
			actions = { "use", "drop" }
		elseif def.type == "placeable" then
			actions = { "place", "drop" }
		elseif def.type == "consumable" then
			actions = { "consume", "drop" }
		else
			actions = { "drop" } -- resources/misc: nothing to use or equip
		end
		-- "Dividir" solo tiene sentido para stacks de más de 1 (para tirar
		-- una parte específica al piso y dejar el resto en el inventario).
		-- Los items rolleados (meta) nunca llegan con quantity > 1, así que
		-- ya quedan afuera por esta misma condición.
		if def.stackable and (entry.quantity or 1) > 1 then
			table.insert(actions, #actions, "split") -- justo antes de "Soltar"
		end
		return actions
	end

	-- Equip the entry into the first free accepting slot; does nothing if
	-- every accepting slot is taken. Used by the shift-click shortcut, which
	-- is intentionally "never swap" (see its own comment below).
	local function equipEntry(entry)
		local def = Items.get(entry.itemId)
		local slotIndex = def and shiftEquipSlot(def)
		if not (slotIndex and moveItemRemote) then
			return
		end
		hideTooltip()
		task.spawn(function()
			local ok, result = pcall(function()
				return moveItemRemote:InvokeServer(
					{ containerId = entry.containerId, x = entry.x, y = entry.y },
					{ containerId = "equipment", x = slotIndex, y = 0 }
				)
			end)
			if ok and typeof(result) == "table" and result.ok == true then
				Sfx.play("equip")
			end
		end)
	end

	-- Equip for the "Usar"/"Colocar" context menu actions: prefer a free
	-- accepting slot like equipEntry above, but when every accepting slot is
	-- full, swap into the first one instead of doing nothing — equipFromGrid
	-- (the 1/2-key shortcut's logic) already unequips that occupant into a
	-- free grid spot first, or bails with a "No room to unequip" hint if
	-- there isn't one.
	local function equipEntrySwap(entry)
		local def = Items.get(entry.itemId)
		if not def then
			return
		end
		local slotIndex = shiftEquipSlot(def)
		if not slotIndex then
			for i, slotName in ipairs(Items.EQUIPMENT_SLOTS) do
				if Items.slotAccepts(slotName, def) then
					slotIndex = i - 1
					break
				end
			end
		end
		if not slotIndex then
			return
		end
		hideTooltip()
		equipFromGrid(entry, slotIndex)
	end

	-- Throw the entry onto the ground. Shared logic with drag-to-world-drop
	-- (endDrag's isWorldDrop branch): optimistic removal now, revert only if
	-- the server rejects it.
	local function dropEntry(entry)
		local from = { containerId = entry.containerId, x = entry.x, y = entry.y }
		local snapshot = applyOptimisticDrop(from)
		if not snapshot then
			return
		end
		render(currentInventory)
		local generationAtMove = serverGeneration
		task.spawn(function()
			local ok, result = false, nil
			if dropItemRemote then
				ok, result = pcall(function()
					return dropItemRemote:InvokeServer(from)
				end)
			end
			local accepted = ok and typeof(result) == "table" and result.ok == true
			if not accepted and serverGeneration == generationAtMove then
				currentInventory = snapshot
				render(snapshot)
			end
		end)
	end

	-- No consumable items exist yet, so this action id is currently
	-- unreachable from actionIdsFor — kept as the one place to wire up once
	-- food/potions land and a "ConsumeItem" RemoteFunction exists server-side.
	local function consumeEntry(entry)
		local consumeRemote = Remotes.getFunction("ConsumeItem")
		if not consumeRemote then
			return
		end
		hideTooltip()
		task.spawn(function()
			pcall(function()
				return consumeRemote:InvokeServer({ containerId = entry.containerId, x = entry.x, y = entry.y })
			end)
		end)
	end

	-- Unequip: move the entry (from an equipment slot) into the first free
	-- grid spot. Same move the equipment slot's shift-click already does —
	-- factored out so the "Desequipar" context menu action can share it.
	local function unequipEntry(entry)
		local spot = findFreeSpotFor(entry.itemId)
		if not spot then
			hoverLabel.Text = "No room to unequip"
			return
		end
		if not moveItemRemote then
			return
		end
		hideTooltip()
		local slotRef = { containerId = entry.containerId, x = entry.x, y = entry.y }
		task.spawn(function()
			local ok, result = pcall(function()
				return moveItemRemote:InvokeServer(slotRef, spot)
			end)
			if ok and typeof(result) == "table" and result.ok == true then
				Sfx.play("unequip")
			end
		end)
	end

	-- ---- split stack modal ("Dividir") ---------------------------------------
	-- Quantity picker for stackable resources (baba de slime, madera, etc.):
	-- separa una parte del stack en un casillero vacío nuevo del inventario,
	-- sin tirar nada al piso — el jugador decide después, con el "Soltar" de
	-- siempre, si quiere tirar esa parte (por ejemplo para dársela a otro
	-- jugador) o no. El server elige el casillero libre y valida la
	-- cantidad (ver inventory.js splitStack).
	local splitModal = Instance.new("Frame")
	splitModal.Name = "SplitStackModal"
	splitModal.Size = UDim2.new(0, 260, 0, 190)
	splitModal.Position = UDim2.new(0.5, 0, 0.5, 0)
	splitModal.AnchorPoint = Vector2.new(0.5, 0.5)
	splitModal.Visible = false
	splitModal.ZIndex = 60
	splitModal.Parent = gui
	UIKit.stylePanel(splitModal)
	UIKit.addShadow(splitModal)
	UIKit.autoScale(splitModal)

	local splitModalTitle = makeLabel(
		splitModal,
		"Dividir stack",
		Theme.Text.Title,
		Theme.Semantic.TextTitle,
		Theme.Font.DisplayBold
	)
	splitModalTitle.Size = UDim2.new(1, -40, 0, 26)
	splitModalTitle.Position = UDim2.new(0, 12, 0, 10)
	splitModalTitle.ZIndex = 60

	local splitModalClose = UIKit.closeButton(splitModal)
	splitModalClose.Position = UDim2.new(1, -6, 0, 6)
	splitModalClose.AnchorPoint = Vector2.new(1, 0)

	local splitItemLabel = makeLabel(splitModal, "", Theme.Text.Sm, COLORS.textDim)
	splitItemLabel.Size = UDim2.new(1, -24, 0, 18)
	splitItemLabel.Position = UDim2.new(0, 12, 0, 40)
	splitItemLabel.ZIndex = 60

	-- fila del stepper: [-]  [ 12 ]  [+]
	local splitStepMinus = UIKit.ghostButton(splitModal, "-")
	splitStepMinus.Size = UDim2.new(0, 34, 0, 34)
	splitStepMinus.Position = UDim2.new(0, 12, 0, 66)

	local splitAmountBox = Instance.new("TextBox")
	splitAmountBox.Name = "SplitAmountBox"
	splitAmountBox.Size = UDim2.new(1, -152, 0, 34)
	splitAmountBox.Position = UDim2.new(0, 54, 0, 66)
	splitAmountBox.BackgroundColor3 = COLORS.section
	splitAmountBox.BorderSizePixel = 0
	splitAmountBox.FontFace = Theme.Font.BodyBold
	splitAmountBox.TextSize = Theme.Text.Lg
	splitAmountBox.TextColor3 = COLORS.text
	splitAmountBox.TextXAlignment = Enum.TextXAlignment.Center
	splitAmountBox.Text = "1"
	splitAmountBox.ClearTextOnFocus = false
	splitAmountBox.ZIndex = 60
	splitAmountBox.Parent = splitModal

	local splitStepPlus = UIKit.ghostButton(splitModal, "+")
	splitStepPlus.Size = UDim2.new(0, 34, 0, 34)
	splitStepPlus.Position = UDim2.new(1, -46, 0, 66)

	local splitHalfBtn = UIKit.ghostButton(splitModal, "Mitad")
	splitHalfBtn.Size = UDim2.new(0, 110, 0, 26)
	splitHalfBtn.Position = UDim2.new(0, 12, 0, 108)
	splitHalfBtn.TextSize = Theme.Text.Sm

	local splitMaxBtn = UIKit.ghostButton(splitModal, "Máx")
	splitMaxBtn.Size = UDim2.new(0, 110, 0, 26)
	splitMaxBtn.Position = UDim2.new(1, -122, 0, 108)
	splitMaxBtn.TextSize = Theme.Text.Sm

	local splitConfirmBtn = UIKit.primaryButton(splitModal, "Dividir")
	splitConfirmBtn.Size = UDim2.new(1, -24, 0, 32)
	splitConfirmBtn.Position = UDim2.new(0, 12, 1, -42)

	local splitTarget = nil -- inventory entry el modal está editando
	local splitCap = 1 -- tope = quantity - 1 (dividir "todo" no es dividir nada, así que no se ofrece)

	local function clampSplitAmount(n)
		n = math.floor(tonumber(n) or 1)
		return math.clamp(n, 1, math.max(splitCap, 1))
	end

	local function setSplitAmount(n)
		splitAmountBox.Text = tostring(clampSplitAmount(n))
	end

	splitStepMinus.Activated:Connect(function()
		setSplitAmount((tonumber(splitAmountBox.Text) or 1) - 1)
	end)
	splitStepPlus.Activated:Connect(function()
		setSplitAmount((tonumber(splitAmountBox.Text) or 1) + 1)
	end)
	splitHalfBtn.Activated:Connect(function()
		setSplitAmount(math.floor((splitCap + 1) / 2))
	end)
	splitMaxBtn.Activated:Connect(function()
		setSplitAmount(splitCap)
	end)
	splitAmountBox.FocusLost:Connect(function()
		setSplitAmount(splitAmountBox.Text)
	end)

	local function closeSplitModal()
		splitModal.Visible = false
		splitTarget = nil
	end
	splitModalClose.Activated:Connect(closeSplitModal)

	-- Abre el picker para `entry` (siempre un stack apilable con quantity > 1
	-- del grid principal — actionIdsFor solo ofrece "split" para esos).
	local function openSplitModal(entry)
		local def = Items.get(entry.itemId)
		splitTarget = entry
		local quantity = math.max(entry.quantity or 1, 1)
		splitCap = math.max(quantity - 1, 1)
		splitItemLabel.Text = (def and def.name or entry.itemId) .. " — tenés " .. tostring(quantity) .. "x"
		setSplitAmount(math.max(1, math.floor(quantity / 2)))
		splitModal.Visible = true
	end

	-- Divide `amount` de `entry` en un stack nuevo, en el primer casillero
	-- libre del grid — el resto se queda donde estaba. A diferencia de
	-- dropEntry/throwStack esto no es optimista: el server es quien decide
	-- en qué casillero libre entra la parte nueva (no lo podemos adivinar
	-- del lado del cliente sin arriesgarnos a un resultado distinto), así
	-- que solo pedimos y esperamos el push de InventoryUpdated para
	-- refrescar el grid — mismo patrón que usa el botón "Ordenar".
	local function confirmSplit(entry, amount)
		amount = clampSplitAmount(amount)
		task.spawn(function()
			if splitStackRemote then
				pcall(function()
					splitStackRemote:InvokeServer({
						containerId = entry.containerId,
						x = entry.x,
						y = entry.y,
					}, amount)
				end)
			end
		end)
	end

	splitConfirmBtn.Activated:Connect(function()
		if not splitTarget then
			return
		end
		local entry, amount = splitTarget, tonumber(splitAmountBox.Text) or 1
		closeSplitModal()
		confirmSplit(entry, amount)
	end)

	local ACTION_HANDLERS = {
		use = equipEntrySwap,
		place = equipEntrySwap,
		consume = consumeEntry,
		split = openSplitModal,
		drop = dropEntry,
		unequip = unequipEntry,
	}

	local contextMenu = Instance.new("Frame")
	contextMenu.Name = "ItemContextMenu"
	contextMenu.AutomaticSize = Enum.AutomaticSize.Y
	contextMenu.Size = UDim2.new(0, 130, 0, 0)
	contextMenu.BackgroundColor3 = COLORS.section
	contextMenu.BorderSizePixel = 0
	contextMenu.Visible = false
	contextMenu.ZIndex = 70
	contextMenu.Parent = gui

	local contextMenuStroke = Instance.new("UIStroke")
	contextMenuStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	contextMenuStroke.Thickness = 1
	contextMenuStroke.Color = Theme.Semantic.BorderDivider
	contextMenuStroke.Parent = contextMenu

	UIKit.addShadow(contextMenu, 10)

	local contextMenuLayout = Instance.new("UIListLayout")
	contextMenuLayout.SortOrder = Enum.SortOrder.LayoutOrder
	contextMenuLayout.Parent = contextMenu

	local contextMenuEntry = nil -- the inventory entry the open menu targets

	local function closeContextMenu()
		contextMenu.Visible = false
		contextMenuEntry = nil
	end

	local function openContextMenu(entry, screenX, screenY)
		if drag then
			return
		end
		hideTooltip()
		contextMenuEntry = entry

		for _, child in ipairs(contextMenu:GetChildren()) do
			if child:IsA("TextButton") then
				child:Destroy()
			end
		end

		local def = Items.get(entry.itemId)
		local actionIds = actionIdsFor(entry, def)
		for _, actionId in ipairs(actionIds) do
			local button = Instance.new("TextButton")
			button.AutoButtonColor = false
			button.BackgroundColor3 = COLORS.section
			button.BorderSizePixel = 0
			button.Size = UDim2.new(1, 0, 0, 30)
			button.FontFace = Theme.Font.BodyBold
			button.TextSize = Theme.Text.Sm
			button.TextColor3 = actionId == "drop" and COLORS.bad or COLORS.text
			button.Text = ACTION_LABELS[actionId]
			button.ZIndex = 71
			button.Parent = contextMenu
			UIKit.hover(button, COLORS.section, Theme.Color.Ink650)

			button.Activated:Connect(function()
				local targetEntry = contextMenuEntry
				closeContextMenu()
				local handler = targetEntry and ACTION_HANDLERS[actionId]
				if handler then
					handler(targetEntry)
				end
			end)
		end

		local s = UIKit.scaleFactor() -- rendered menu size is design px × scale
		local guiSize = gui.AbsoluteSize
		local menuH = #actionIds * 30 * s
		contextMenu.Position = UDim2.fromOffset(
			math.min(screenX, guiSize.X - 130 * s),
			math.min(screenY, guiSize.Y - menuH)
		)
		contextMenu.Visible = true
	end

	-- Any click outside the open menu dismisses it (both mouse buttons —
	-- right-clicking a different tile should close-then-reopen cleanly).
	UserInputService.InputBegan:Connect(function(input)
		if not contextMenu.Visible then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.MouseButton2 then
			if not pointIn(contextMenu, mouse.X, mouse.Y) then
				closeContextMenu()
			end
		end
	end)

	-- ---- grid tiles (diffed: reused across renders, thumbnails built once) ---
	-- records: array of { frame, thumb, qty, badge, itemId, entry, used }
	local tileRecords = {}

	-- The quick-bind key label for an item, or nil (slot 9 renders as "0").
	local function bindKeyLabelFor(itemId)
		for slotIndex = 2, 9 do
			if HotbarBinds.get(slotIndex) == itemId then
				return tostring((slotIndex + 1) % 10)
			end
		end
		return nil
	end

	local function refreshBindBadges()
		for _, record in ipairs(tileRecords) do
			local label = bindKeyLabelFor(record.itemId)
			record.badge.Text = label or ""
			record.badge.Visible = label ~= nil
			-- The level label shares the top-right corner: give the badge room.
			record.levelLabel.Size = UDim2.new(1, label ~= nil and -24 or -6, 0, 12)
		end
	end

	local function createTileRecord(entry)
		local def = Items.get(entry.itemId)
		local record = { itemId = entry.itemId, entry = entry }

		local tile = Instance.new("TextButton")
		tile.Text = ""
		tile.AutoButtonColor = false
		tile.BackgroundColor3 = COLORS.tile
		tile.BackgroundTransparency = 0.15 -- a solid raised well (big items kept
		-- vanishing into the background and reading as holes in the grid)
		tile.BorderSizePixel = 0
		tile.ZIndex = 3
		tile.Parent = itemsLayer
		record.frame = tile

		local stroke = Instance.new("UIStroke")
		-- The tile is a TextButton: Contextual (the default) would stroke its
		-- empty TEXT, so the rarity border never showed. Border it explicitly.
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Thickness = 1
		stroke.Color = COLORS.tileStroke
		stroke.Parent = tile
		record.stroke = stroke

		-- Rarity inner glow (uncommon+), retinted per entry in updateTileRecord.
		record.glow = UIKit.addGlow(tile, Color3.new(1, 1, 1), 0.78)
		if record.glow then
			record.glow.Visible = false
			record.glow.ZIndex = 3
		end

		local thumb = makeViewport(tile)
		thumb.ZIndex = 4
		record.thumb = thumb
		-- The thumbnail is built exactly once per record; renders only move it.
		if not ItemModels.preview(thumb, entry.itemId) then
			local fallback = makeLabel(tile, def and def.name or entry.itemId, 11)
			fallback.Size = UDim2.new(1, -6, 1, -6)
			fallback.Position = UDim2.new(0, 3, 0, 3)
			fallback.TextWrapped = true
			fallback.ZIndex = 4
		end

		local qty = makeLabel(tile, "", 13, COLORS.gold)
		qty.Size = UDim2.new(1, -6, 0, 14)
		qty.Position = UDim2.new(0, 3, 1, -16)
		qty.TextXAlignment = Enum.TextXAlignment.Right
		qty.ZIndex = 5
		record.qty = qty

		-- Quick-bind badge, top-right corner ("4" = bound to key 4).
		local badge = makeLabel(tile, "", 12, COLORS.gold)
		badge.Size = UDim2.new(0, 16, 0, 14)
		badge.Position = UDim2.new(1, -18, 0, 2)
		badge.TextXAlignment = Enum.TextXAlignment.Right
		badge.Visible = false
		badge.ZIndex = 5
		record.badge = badge

		-- Item level, top-right ("Lv 3"; red = above your class level, so it
		-- can't be equipped yet). Slides left of the bind badge when both show
		-- (refreshBindBadges keeps the margin in sync).
		local levelLabel = makeLabel(tile, "", 11, COLORS.textDim)
		levelLabel.Size = UDim2.new(1, -6, 0, 12)
		levelLabel.Position = UDim2.new(0, 3, 0, 3)
		levelLabel.TextXAlignment = Enum.TextXAlignment.Right
		levelLabel.ZIndex = 5
		record.levelLabel = levelLabel

		-- Mini trait hexes, bottom-left (the qty label keeps bottom-right).
		record.badgeRow = makeBadgeRow(tile, 5)

		tile.MouseEnter:Connect(function()
			hovered = record.entry
			local currentDef = Items.get(record.itemId)
			hoverLabel.Text = currentDef and currentDef.name or record.itemId
			scheduleTooltip(record.entry, nil, equippedCounterpart(record.entry))
		end)
		tile.MouseLeave:Connect(function()
			if hovered == record.entry then
				hovered = nil
				hoverLabel.Text = ""
			end
			hideTooltip()
		end)
		tile.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton2 then
				local shiftHeld = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
					or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
				if shiftHeld and not drag then
					-- Shift+right-click: same as picking "Usar"/"Colocar" from
					-- the menu, but immediate — swaps the equipped item if
					-- every accepting slot is already full.
					equipEntrySwap(record.entry)
					return
				end
				openContextMenu(record.entry, mouse.X, mouse.Y)
				return
			end
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				local entryNow = record.entry
				local shiftHeld = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
					or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
				if shiftHeld and not drag then
					-- Shift-click: equip into a free accepting slot; occupied
					-- (or not equippable) → do nothing, and never start a drag.
					local def = Items.get(entryNow.itemId)
					local slotIndex = def and shiftEquipSlot(def)
					local levelOk, needLevel = equipLevelOk(entryNow)
					if slotIndex and not levelOk then
						hoverLabel.Text = ("Requires Lv %d"):format(needLevel)
					elseif slotIndex and moveItemRemote then
						hideTooltip()
						task.spawn(function()
							local ok, result = pcall(function()
								return moveItemRemote:InvokeServer(
									{ containerId = "main", x = entryNow.x, y = entryNow.y },
									{ containerId = "equipment", x = slotIndex, y = 0 }
								)
							end)
							if ok and typeof(result) == "table" and result.ok == true then
								Sfx.play("equip")
							end
						end)
					end
					return
				end
				beginDrag(entryNow, { containerId = "main", x = entryNow.x, y = entryNow.y }, tile)
			end
		end)

		table.insert(tileRecords, record)
		return record
	end

	local function updateTileRecord(record, entry)
		record.entry = entry
		local w, h = Items.sizeFor(entry.itemId, entry.rotated)
		record.frame.Size = UDim2.new(0, w * CELL - 2, 0, h * CELL - 2)
		record.frame.Position = UDim2.new(0, entry.x * CELL + 1, 0, entry.y * CELL + 1)
		record.qty.Text = entry.quantity > 1 and tostring(entry.quantity) or ""
		-- Border, glow and trait badges track the ENTRY, not the record:
		-- reused tiles match by itemId, and two instances of the same item
		-- can carry different rolls.
		local def = Items.get(entry.itemId)
		local rarity = Rarity.forEntry(entry, def)
		record.stroke.Color = rarity.color
		if record.glow then
			record.glow.Visible = rarity.hasGlow
			record.glow.ImageColor3 = rarity.glowColor
		end
		fillTraitBadges(record.badgeRow, entry, def)
		local itemLevel = Traits.entryInfo(entry, def)
		record.levelLabel.Text = itemLevel > 0 and ("Lv %d"):format(itemLevel) or ""
		record.levelLabel.TextColor3 = itemLevel > (player:GetAttribute("Level") or 1) and COLORS.bad
			or COLORS.textDim
	end

	-- ---- rendering (diff) -----------------------------------------------------
	render = function(inventory)
		if typeof(inventory) ~= "table" then
			inventory = {}
		end
		currentInventory = inventory
		hovered = nil
		hoverLabel.Text = ""
		hideTooltip()
		closeContextMenu()

		-- A re-render mid-drag means the world changed under us; cancel cleanly.
		if drag then
			endDrag(false)
		end

		local mainEntries = {}
		local equipEntries = {} -- [slotName] = entry
		for _, entry in ipairs(inventory) do
			if entry.containerId == "main" then
				mainEntries[#mainEntries + 1] = entry
			elseif entry.containerId == "equipment" then
				local slotName = Items.EQUIPMENT_SLOTS[entry.x + 1]
				if slotName then
					equipEntries[slotName] = entry
				end
			end
		end

		-- Match entries to existing tiles: same item at the same spot first
		-- (untouched tiles), then any leftover tile of the same item (moved
		-- tiles keep their thumbnail), then create/destroy the rest.
		for _, record in ipairs(tileRecords) do
			record.used = false
		end
		local unmatched = {}
		for _, entry in ipairs(mainEntries) do
			local exact
			for _, record in ipairs(tileRecords) do
				if not record.used and record.itemId == entry.itemId
					and record.entry.x == entry.x and record.entry.y == entry.y then
					exact = record
					break
				end
			end
			if exact then
				exact.used = true
				updateTileRecord(exact, entry)
			else
				unmatched[#unmatched + 1] = entry
			end
		end
		for _, entry in ipairs(unmatched) do
			local match
			for _, record in ipairs(tileRecords) do
				if not record.used and record.itemId == entry.itemId then
					match = record
					break
				end
			end
			if not match then
				match = createTileRecord(entry)
			end
			match.used = true
			updateTileRecord(match, entry)
		end
		for i = #tileRecords, 1, -1 do
			local record = tileRecords[i]
			if not record.used then
				record.frame:Destroy()
				table.remove(tileRecords, i)
			end
		end

		-- Equipment slots: re-preview only when the item actually changed.
		local playerLevel = player:GetAttribute("Level") or 1
		for slotName, slot in pairs(equipSlots) do
			local entry = equipEntries[slotName]
			slot.entry = entry
			if entry then
				if slot.shownId ~= entry.itemId then
					slot.shownId = entry.itemId
					ItemModels.preview(slot.thumb, entry.itemId)
				end
				slot.nameLabel.Visible = false
				local def = Items.get(entry.itemId)
				if slot.glow then
					local rarity = Rarity.forEntry(entry, def)
					slot.glow.Visible = rarity.hasGlow
					slot.glow.ImageColor3 = rarity.glowColor
				end
				fillTraitBadges(slot.badgeRow, entry, def)
				local entryLevel = Traits.entryInfo(entry, def)
				local inert = entryLevel > playerLevel
				slot.inertOverlay.Visible = inert
				slot.inertLabel.Visible = inert
				slot.inertLabel.Text = inert and ("Lv " .. entryLevel) or ""
			else
				if slot.shownId then
					slot.shownId = nil
					slot.thumb:ClearAllChildren()
				end
				slot.nameLabel.Visible = true
				if slot.glow then
					slot.glow.Visible = false
				end
				fillTraitBadges(slot.badgeRow, nil, nil)
				slot.inertOverlay.Visible = false
				slot.inertLabel.Visible = false
			end
		end
		resetEquipStrokes() -- rarity borders track the (new) occupants

		refreshBindBadges()
	end

	-- Authoritative updates from the server bump the generation so pending
	-- optimistic reverts know to stand down.
	local function renderFromServer(inventory)
		serverGeneration += 1
		render(inventory)
	end

	-- Equipment slots: drag out, shift-click, or right-click → "Desequipar"
	-- to unequip (and hover shows the name).
	for slotName, slot in pairs(equipSlots) do
		slot.frame.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton2 and slot.entry then
				openContextMenu(slot.entry, mouse.X, mouse.Y)
				return
			end
			if input.UserInputType == Enum.UserInputType.MouseButton1 and slot.entry then
				local entryNow = slot.entry
				local slotRef = { containerId = "equipment", x = SLOT_INDEX[slotName], y = 0 }
				local shiftHeld = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
					or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
				if shiftHeld and not drag then
					-- Shift-click: unequip into the first free grid spot.
					unequipEntry(entryNow)
					return
				end
				beginDrag(entryNow, slotRef, slot.frame)
			end
		end)
		slot.frame.MouseEnter:Connect(function()
			if slot.entry then
				local def = Items.get(slot.entry.itemId)
				hoverLabel.Text = def and def.name or slot.entry.itemId
				scheduleTooltip(slot.entry)
			end
		end)
		slot.frame.MouseLeave:Connect(function()
			hoverLabel.Text = ""
			hideTooltip()
		end)
	end

	-- ---- effects panel -------------------------------------------------------
	local function refreshEffects()
		for _, child in ipairs(effectsList:GetChildren()) do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		local now = Workspace:GetServerTimeNow()
		for name, value in pairs(player:GetAttributes()) do
			local effectId = Effects.idFromAttribute(name)
			local def = effectId and Effects.get(effectId)
			if def and typeof(value) == "number" and value > now then
				local row = Instance.new("Frame")
				row.Size = UDim2.new(1, 0, 0, 24)
				row.BackgroundTransparency = 1
				row.Parent = effectsList

				local icon = Instance.new("Frame")
				icon.Size = UDim2.new(0, 18, 0, 18)
				icon.Position = UDim2.new(0, 0, 0, 3)
				icon.BackgroundColor3 = def.color or COLORS.textDim
				icon.BorderSizePixel = 0
				icon.Parent = row

				local text = makeLabel(row, string.format("%s  %.0fs", def.name, value - now), 12)
				text.Size = UDim2.new(1, -26, 1, 0)
				text.Position = UDim2.new(0, 26, 0, 0)
				text.TextXAlignment = Enum.TextXAlignment.Left
			end
		end
	end

	player.AttributeChanged:Connect(function(name)
		if Effects.idFromAttribute(name) then
			refreshEffects()
		end
	end)
	task.spawn(function()
		while true do
			task.wait(0.5)
			if isOpen then
				refreshEffects()
			end
		end
	end)

	-- ---- gold ----------------------------------------------------------------
	local function updateGold()
		goldLabel.Text = ("◈ %d Gold"):format(player:GetAttribute("Gold") or 0)
	end
	player:GetAttributeChangedSignal("Gold"):Connect(updateGold)
	updateGold()

	-- Leveling (or switching class) moves the inert gate on equipped gear.
	player:GetAttributeChangedSignal("Level"):Connect(function()
		render(currentInventory)
	end)

	-- ---- class picker ----------------------------------------------------
	local switchClassRemote = Remotes.getFunction("SwitchClass")
	local classLevelsRemote = Remotes.getFunction("RequestClassLevels")

	local classModal = Instance.new("Frame")
	classModal.Size = UDim2.new(0, 380, 0, 330)
	classModal.Position = UDim2.new(0.5, 0, 0.5, 0)
	classModal.AnchorPoint = Vector2.new(0.5, 0.5)
	classModal.Visible = false
	classModal.ZIndex = 20
	classModal.Parent = gui
	UIKit.stylePanel(classModal)
	UIKit.addShadow(classModal)
	UIKit.autoScale(classModal)

	local classModalTitle = makeLabel(
		classModal,
		"Elegí tu clase",
		Theme.Text.Title,
		Theme.Semantic.TextTitle,
		Theme.Font.DisplayBold
	)
	classModalTitle.Size = UDim2.new(1, -16, 0, 30)
	classModalTitle.Position = UDim2.new(0, 8, 0, 8)
	classModalTitle.ZIndex = 20

	local classModalClose = UIKit.closeButton(classModal)
	classModalClose.Position = UDim2.new(1, -6, 0, 6)
	classModalClose.AnchorPoint = Vector2.new(1, 0)

	local CARD_H = 62
	local classCards = {}
	for i, classId in ipairs(Classes.order) do
		local def = Classes.get(classId)

		local card = Instance.new("Frame")
		card.Size = UDim2.new(1, -16, 0, CARD_H)
		card.Position = UDim2.new(0, 8, 0, 44 + (i - 1) * (CARD_H + 8))
		card.BackgroundColor3 = COLORS.section
		card.BorderSizePixel = 0
		card.ZIndex = 20
		card.Parent = classModal

		local cardCorner = Instance.new("UICorner")
		cardCorner.CornerRadius = UDim.new(0, 6)
		cardCorner.Parent = card

		local nameLabel =
			makeLabel(card, def.name, Theme.Text.Lg, Theme.Semantic.TextHero, Theme.Font.DisplayBold)
		nameLabel.Size = UDim2.new(1, -90, 0, 20)
		nameLabel.Position = UDim2.new(0, 10, 0, 6)
		nameLabel.ZIndex = 20

		local descLabel = makeLabel(card, def.description, 11, COLORS.textDim)
		descLabel.Size = UDim2.new(1, -20, 0, 30)
		descLabel.Position = UDim2.new(0, 10, 0, 26)
		descLabel.TextWrapped = true
		descLabel.ZIndex = 20

		local useBtn = UIKit.primaryButton(card, "Usar")
		useBtn.Size = UDim2.new(0, 74, 0, 26)
		useBtn.Position = UDim2.new(1, -10, 0, 8)
		useBtn.AnchorPoint = Vector2.new(1, 0)
		useBtn.TextSize = Theme.Text.Sm
		useBtn.ZIndex = 21

		useBtn.Activated:Connect(function()
			useBtn.Text = "..."
			task.spawn(function()
				local ok, result = pcall(function()
					return switchClassRemote:InvokeServer(classId)
				end)
				useBtn.Text = "Usar"
				if ok and result and result.ok then
					classModal.Visible = false
				end
			end)
		end)

		classCards[classId] = { card = card, nameLabel = nameLabel, useBtn = useBtn }
	end

	-- Fetches every class's level (so the picker can show "Mage Lvl. 3" even
	-- for classes you're not currently playing) and highlights the active one.
	local function openClassPicker()
		classModal.Visible = true
		task.spawn(function()
			local ok, levels = pcall(function()
				return classLevelsRemote:InvokeServer()
			end)
			local activeClass = player:GetAttribute("Class")
			for classId, widgets in pairs(classCards) do
				local def = Classes.get(classId)
				local lv = ok and levels and levels[classId]
				local levelText = lv and string.format(" — Lvl. %d", lv.level) or ""
				widgets.nameLabel.Text = def.name .. levelText
				local isActive = classId == activeClass
				widgets.card.BackgroundColor3 = isActive and Theme.Color.Ember600 or COLORS.section
				widgets.useBtn.Text = isActive and "Actual" or "Usar"
				widgets.useBtn.AutoButtonColor = not isActive
			end
		end)
	end

	switchClassBtn.Activated:Connect(openClassPicker)
	classModalClose.Activated:Connect(function()
		classModal.Visible = false
	end)

	-- ---- toggling ------------------------------------------------------------
	local function toggle()
		isOpen = not isOpen
		-- Un solo choke point para botón (top-right) Y tecla B — así ambos
		-- caminos suenan igual, en vez de depender del uiClick genérico que
		-- solo dispara si tocaste el botón.
		Sfx.play(isOpen and "panelOpen" or "panelClose")
		-- Free the cursor (via ShiftLockController) while the panel is open.
		ClientState.inventoryOpen = isOpen
		if isOpen then
			-- The store screen shows this same grid; one of the two at a time.
			if ClientState.storeOpen and ClientState.closeStore then
				ClientState.closeStore()
			end
			if ClientState.chestOpen and ClientState.closeChest then
				ClientState.closeChest()
			end
			refreshEffects()
			refreshDoll()
		else
			endDrag(false)
			hideTooltip()
			closeContextMenu()
			closeSplitModal()
		end
		TweenService:Create(panel, SLIDE_TWEEN, { Position = isOpen and OPEN_POS or CLOSED_POS }):Play()
	end
	ClientState.closeInventory = function()
		if isOpen then
			toggle()
		end
	end

	local openBtn = TopRightMenu.addButton("Inventory (B)", 1, 34)
	openBtn.Name = "InventoryButton"
	openBtn.TextSize = Theme.Text.Body

	openBtn.Activated:Connect(toggle)
	closeBtn.Activated:Connect(toggle)
	sortBtn.Activated:Connect(function()
		task.spawn(function()
			if sortRemote then
				pcall(function()
					sortRemote:InvokeServer()
				end)
			end
		end)
	end)

	-- (Re)build the doll whenever the character spawns — pre-warming it so
	-- the first open never pays the clone cost mid-toggle.
	player.CharacterAdded:Connect(function(character)
		task.spawn(function()
			character:WaitForChild("HumanoidRootPart", 5)
			refreshDoll()
		end)
	end)
	if player.Character then
		task.defer(refreshDoll)
	end

	-- Bound action (not raw InputBegan) so the key works without 3D-viewport
	-- keyboard focus; it still won't fire while a TextBox is captured.
	ContextActionService:BindAction("ToggleInventory", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			toggle()
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.B)

	-- ---- drag/bind keys ------------------------------------------------------
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if not isOpen then
			return
		end
		if drag and input.KeyCode == Enum.KeyCode.R then
			-- Rotate the carried item; the ghost and preview follow.
			drag.rotated = not drag.rotated
			buildGhost()
			updateDrag()
			return
		end
		if gameProcessed then
			return
		end
		-- 1/2 over a grid item: equip it into weapon/offhand (swap included).
		local equipSlotIndex = EQUIP_KEYS[input.KeyCode]
		if equipSlotIndex and hovered and not drag then
			local entry = hovered
			if entry.containerId == "main" then
				local def = Items.get(entry.itemId)
				local slotName = Items.EQUIPMENT_SLOTS[equipSlotIndex + 1]
				if def and Items.slotAccepts(slotName, def) then
					local levelOk, needLevel = equipLevelOk(entry)
					if levelOk then
						task.spawn(equipFromGrid, entry, equipSlotIndex)
					else
						hoverLabel.Text = ("Requires Lv %d"):format(needLevel)
					end
				end
			end
			return
		end
		-- Q over an item: throw it on the ground (same verb as dragging it out).
		if input.KeyCode == Enum.KeyCode.Q and hovered and not drag then
			local entry = hovered
			hideTooltip()
			throwStack({ containerId = entry.containerId, x = entry.x, y = entry.y })
			return
		end
		local bindSlot = BIND_KEYS[input.KeyCode]
		if bindSlot and hovered then
			local def = Items.get(hovered.itemId)
			-- Decided rule: only tools and consumables are quick-bindable
			-- (weapons live on the reserved 1/2 keys).
			if def and (def.type == "tool" or def.type == "consumable") then
				HotbarBinds.set(bindSlot, hovered.itemId)
			end
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if drag and input.UserInputType == Enum.UserInputType.MouseButton1 then
			endDrag(true)
		end
	end)

	HotbarBinds.changed:Connect(refreshBindBadges)

	-- Wire up the remotes in the background so a slow/missing server can never
	-- block the keybind above.
	task.spawn(function()
		moveItemRemote = Remotes.getFunction("MoveItem")
		sortRemote = Remotes.getFunction("SortInventory")
		dropItemRemote = Remotes.getFunction("DropItem")
		splitStackRemote = Remotes.getFunction("SplitStack")

		local inventoryUpdated = Remotes.get("InventoryUpdated")
		inventoryUpdated.OnClientEvent:Connect(renderFromServer)

		local requestInventory = Remotes.getFunction("RequestInventory")
		local ok, inventory = pcall(function()
			return requestInventory:InvokeServer()
		end)
		if ok then
			renderFromServer(inventory)
		end
	end)
end

return InventoryUI