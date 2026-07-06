-- Diablo-style HUD: a health orb (bottom-left), a mana orb (bottom-right), and
-- a functional hotbar of item sockets between them.
--   * Health reads the local Humanoid directly (HP replicates automatically).
--   * Mana reads the "Mana"/"MaxMana" Player attributes set by the server's
--     ManaService (attributes replicate to the owner, so no remote is needed).
--   * The hotbar: slots 1/2 are reserved for the equipped
--     main weapons (the paper doll's weapon/offhand slots) and slots 3–0 are
--     player-assigned quick binds (hover an item in the inventory grid and
--     press the key — see HotbarBinds). A bind is either an item or a spell
--     ("spell:<id>", auto-placed on unlock by SpellsClient). Clicking an item
--     slot (or pressing its key) equips/unequips its Tool; a spell slot casts
--     through the CastSpell remote, with a cooldown veil driven by the
--     server's SpellCd_<id> attributes. We hide Roblox's default backpack bar
--     so this is the only hotbar on screen.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")

local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Items = require(Shared:WaitForChild("Items"))
local ItemModels = require(Shared:WaitForChild("ItemModels"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Config = require(Shared:WaitForChild("Config"))
local Effects = require(Shared:WaitForChild("Effects"))
local Spells = require(Shared:WaitForChild("Spells"))
local HotbarBinds = require(script.Parent.HotbarBinds)
local SpellsClient = require(script.Parent.SpellsClient)
local ClientState = require(script.Parent.ClientState)

local player = Players.LocalPlayer

local HudUI = {}

local ORB_SIZE = 108
local ORB_MARGIN = 22
local SLOT = 58
local SLOT_PAD = 8

local HOTBAR_SIZE = 10 -- 1/2 = weapons, 3–0 = quick binds
local WEAPON_SLOTS = 2

local NUMBER_KEYS = {
	Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three,
	Enum.KeyCode.Four, Enum.KeyCode.Five, Enum.KeyCode.Six,
	Enum.KeyCode.Seven, Enum.KeyCode.Eight, Enum.KeyCode.Nine,
	Enum.KeyCode.Zero,
}

-- Display label for slot i (0-based): 1..9 then 0.
local function keyLabelFor(i)
	return tostring((i + 1) % 10)
end

-- Equipment container x → hotbar slot (weapon = 0, offhand = 1).
local SLOT_INDEX = {}
for index, name in ipairs(Items.EQUIPMENT_SLOTS) do
	SLOT_INDEX[name] = index - 1
end

-- Builds a circular "liquid" orb. Returns a setter: update(current, max).
local function makeOrb(parent, anchorCorner, fillColor, rimColor)
	local container = Instance.new("Frame")
	container.Size = UDim2.new(0, ORB_SIZE, 0, ORB_SIZE)
	container.BackgroundColor3 = Color3.fromRGB(14, 14, 18)
	container.BorderSizePixel = 0
	container.ClipsDescendants = true -- clips the fill to the rounded (circular) shape
	if anchorCorner == "left" then
		container.AnchorPoint = Vector2.new(0, 1)
		container.Position = UDim2.new(0, ORB_MARGIN, 1, -ORB_MARGIN)
	else
		container.AnchorPoint = Vector2.new(1, 1)
		container.Position = UDim2.new(1, -ORB_MARGIN, 1, -ORB_MARGIN)
	end
	container.Parent = parent

	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0.5, 0) -- half the size → a circle
	round.Parent = container

	-- Rising liquid: full width so the circular clip shapes it into a disc; only
	-- the flat top edge (the liquid surface) moves as the value changes.
	local fill = Instance.new("Frame")
	fill.AnchorPoint = Vector2.new(0.5, 1)
	fill.Position = UDim2.new(0.5, 0, 1, 0)
	fill.Size = UDim2.new(1, 0, 0, 0)
	fill.BackgroundColor3 = fillColor
	fill.BorderSizePixel = 0
	fill.Parent = container

	-- Vertical sheen so the liquid reads as glassy, not flat.
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, fillColor:Lerp(Color3.new(1, 1, 1), 0.35)),
		ColorSequenceKeypoint.new(1, fillColor:Lerp(Color3.new(0, 0, 0), 0.35)),
	})
	gradient.Parent = fill

	-- Rim ring around the orb (drawn on top, follows the circle).
	local rim = Instance.new("UIStroke")
	rim.Thickness = 3
	rim.Color = rimColor
	rim.Transparency = 0.1
	rim.Parent = container

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, 22)
	label.Position = UDim2.new(0, 0, 0.5, -11)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 17
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Text = ""
	label.Parent = container

	local labelStroke = Instance.new("UIStroke")
	labelStroke.Thickness = 2
	labelStroke.Color = Color3.fromRGB(0, 0, 0)
	labelStroke.Transparency = 0.35
	labelStroke.Parent = label

	return function(current, maximum)
		current = math.max(0, math.floor(current + 0.5))
		maximum = math.max(1, math.floor(maximum + 0.5))
		local frac = math.clamp(current / maximum, 0, 1)
		fill.Size = UDim2.new(1, 0, frac, 0)
		label.Text = string.format("%d / %d", current, maximum)
	end
end

-- Active effects strip (buffs/debuffs), anchored above the health orb so it's
-- always visible during play — not just while the inventory is open. Reads
-- the same Effect_<id> attributes as InventoryUI's panel (see shared/Effects).
local EFFECT_ROW = 22
local function makeEffectsPanel(parent)
	local list = Instance.new("Frame")
	list.Size = UDim2.new(0, 200, 0, 120)
	list.AnchorPoint = Vector2.new(0, 1)
	list.Position = UDim2.new(0, ORB_MARGIN, 1, -(ORB_MARGIN + ORB_SIZE + 14))
	list.BackgroundTransparency = 1
	list.Parent = parent

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.Padding = UDim.new(0, 4)
	layout.Parent = list

	local rows = {} -- [effectId] = { frame, label, fill }

	local function refresh()
		local now = Workspace:GetServerTimeNow()
		local seen = {}
		for name, value in pairs(player:GetAttributes()) do
			local effectId = Effects.idFromAttribute(name)
			local def = effectId and Effects.get(effectId)
			if def and typeof(value) == "number" and value > now then
				seen[effectId] = true
				local row = rows[effectId]
				if not row then
					local frame = Instance.new("Frame")
					frame.Size = UDim2.new(1, 0, 0, EFFECT_ROW)
					frame.BackgroundColor3 = Color3.fromRGB(14, 14, 18)
					frame.BackgroundTransparency = 0.25
					frame.BorderSizePixel = 0
					frame.Parent = list

					local corner = Instance.new("UICorner")
					corner.CornerRadius = UDim.new(0, 5)
					corner.Parent = frame

					local icon = Instance.new("Frame")
					icon.Size = UDim2.new(0, 14, 0, 14)
					icon.Position = UDim2.new(0, 5, 0.5, -9)
					icon.BackgroundColor3 = def.color or Color3.fromRGB(200, 200, 200)
					icon.BorderSizePixel = 0
					icon.Parent = frame

					local iconCorner = Instance.new("UICorner")
					iconCorner.CornerRadius = UDim.new(0.3, 0)
					iconCorner.Parent = icon

					local label = Instance.new("TextLabel")
					label.Size = UDim2.new(1, -28, 1, -4)
					label.Position = UDim2.new(0, 26, 0, 0)
					label.BackgroundTransparency = 1
					label.Font = Enum.Font.GothamMedium
					label.TextSize = 13
					label.TextColor3 = Color3.new(1, 1, 1)
					label.TextXAlignment = Enum.TextXAlignment.Left
					label.Parent = frame

					-- Remaining-duration bar along the bottom of the row.
					local barBg = Instance.new("Frame")
					barBg.Size = UDim2.new(1, -8, 0, 2)
					barBg.Position = UDim2.new(0, 4, 1, -4)
					barBg.BackgroundColor3 = Color3.fromRGB(40, 40, 48)
					barBg.BorderSizePixel = 0
					barBg.Parent = frame

					local fill = Instance.new("Frame")
					fill.Size = UDim2.new(1, 0, 1, 0)
					fill.BackgroundColor3 = def.color or Color3.fromRGB(200, 200, 200)
					fill.BorderSizePixel = 0
					fill.Parent = barBg

					row = { frame = frame, label = label, fill = fill }
					rows[effectId] = row
				end
				row.label.Text = string.format("%s  %.0fs", def.name, value - now)
				-- Diminished applications start below 100% (shorter than the
				-- def duration); that reads correctly — less bar, less CC.
				local frac = math.clamp((value - now) / math.max(def.duration or 1, 0.1), 0, 1)
				row.fill.Size = UDim2.new(frac, 0, 1, 0)
			end
		end
		for effectId, row in pairs(rows) do
			if not seen[effectId] then
				row.frame:Destroy()
				rows[effectId] = nil
			end
		end
	end

	player.AttributeChanged:Connect(function(name)
		if Effects.idFromAttribute(name) then
			refresh()
		end
	end)

	task.spawn(function()
		while true do
			task.wait(0.25)
			refresh() -- also drains the bars/countdowns with no attribute change
		end
	end)
end

-- Builds one hotbar socket (a button). Returns { set, setEquipped }.
-- `reserved` marks the weapon slots (1/2) with a warmer socket tint.
local function makeSlot(parent, order, reserved, onActivated)
	local slot = Instance.new("TextButton")
	slot.Size = UDim2.new(0, SLOT, 0, SLOT)
	slot.LayoutOrder = order
	slot.AutoButtonColor = false
	slot.Text = ""
	slot.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
	slot.BackgroundTransparency = 0.4
	slot.BorderSizePixel = 0
	slot.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = slot

	local baseStroke = reserved and Color3.fromRGB(110, 95, 60) or Color3.fromRGB(70, 70, 85)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1.5
	stroke.Color = baseStroke
	stroke.Transparency = 0.2
	stroke.Parent = slot

	-- Hotkey number, top-left.
	local key = Instance.new("TextLabel")
	key.Size = UDim2.new(0, 14, 0, 12)
	key.Position = UDim2.new(0, 3, 0, 2)
	key.BackgroundTransparency = 1
	key.TextColor3 = reserved and Color3.fromRGB(230, 205, 140) or Color3.fromRGB(180, 180, 195)
	key.Font = Enum.Font.GothamBold
	key.TextXAlignment = Enum.TextXAlignment.Left
	key.TextSize = 11
	key.Text = keyLabelFor(order)
	key.Parent = slot

	-- 3D thumbnail of the item's low-poly model (fills the socket).
	local thumb = Instance.new("ViewportFrame")
	thumb.Size = UDim2.new(1, -4, 1, -4)
	thumb.Position = UDim2.new(0, 2, 0, 2)
	thumb.BackgroundTransparency = 1
	thumb.Ambient = Color3.fromRGB(180, 180, 190)
	thumb.LightColor = Color3.new(1, 1, 1)
	thumb.Parent = slot

	-- Fallback label for items that have no model.
	local name = Instance.new("TextLabel")
	name.Size = UDim2.new(1, -8, 1, -26)
	name.Position = UDim2.new(0, 4, 0, 14)
	name.BackgroundTransparency = 1
	name.TextColor3 = Color3.new(1, 1, 1)
	name.Font = Enum.Font.GothamMedium
	name.TextSize = 11
	name.TextWrapped = true
	name.Text = ""
	name.Parent = slot

	local qty = Instance.new("TextLabel")
	qty.Size = UDim2.new(1, -6, 0, 13)
	qty.Position = UDim2.new(0, 3, 1, -14)
	qty.BackgroundTransparency = 1
	qty.TextColor3 = Color3.fromRGB(255, 220, 120)
	qty.Font = Enum.Font.GothamBold
	qty.TextXAlignment = Enum.TextXAlignment.Right
	qty.TextSize = 13
	qty.Text = ""
	qty.Parent = slot

	-- Spell binds render as an emoji icon (no 3D model to preview).
	local spellIcon = Instance.new("TextLabel")
	spellIcon.Size = UDim2.new(1, 0, 1, -8)
	spellIcon.Position = UDim2.new(0, 0, 0, 4)
	spellIcon.BackgroundTransparency = 1
	spellIcon.Font = Enum.Font.GothamBold
	spellIcon.TextSize = 26
	spellIcon.TextColor3 = Color3.new(1, 1, 1)
	spellIcon.Text = ""
	spellIcon.Visible = false
	spellIcon.ZIndex = 2
	spellIcon.Parent = slot

	-- Cooldown veil: a dark curtain that drains downward as the spell recharges.
	local cdVeil = Instance.new("Frame")
	cdVeil.Size = UDim2.new(1, 0, 0, 0)
	cdVeil.BackgroundColor3 = Color3.fromRGB(8, 8, 12)
	cdVeil.BackgroundTransparency = 0.3
	cdVeil.BorderSizePixel = 0
	cdVeil.Visible = false
	cdVeil.ZIndex = 5
	cdVeil.Parent = slot

	local cdVeilCorner = Instance.new("UICorner")
	cdVeilCorner.CornerRadius = UDim.new(0, 6)
	cdVeilCorner.Parent = cdVeil

	local cdText = Instance.new("TextLabel")
	cdText.Size = UDim2.new(1, 0, 1, 0)
	cdText.BackgroundTransparency = 1
	cdText.Font = Enum.Font.GothamBold
	cdText.TextSize = 16
	cdText.TextColor3 = Color3.new(1, 1, 1)
	cdText.Text = ""
	cdText.Visible = false
	cdText.ZIndex = 6
	cdText.Parent = slot

	slot.Activated:Connect(onActivated)

	local hasItem = false
	local isSpell = false
	local spellDimmed = false -- spell belongs to a class we're not playing
	local shownId = nil -- itemId / "spell:<id>" currently rendered

	local function set(itemId, quantity)
		isSpell = false
		spellIcon.Visible = false
		cdVeil.Visible = false
		cdText.Visible = false
		if itemId then
			hasItem = true
			-- Only rebuild the viewport when the item actually changes.
			if itemId ~= shownId then
				shownId = itemId
				local def = Items.get(itemId)
				if ItemModels.preview(thumb, itemId) then
					name.Text = ""
				else
					name.Text = def and def.name or itemId
				end
			end
			qty.Text = (quantity and quantity > 1) and tostring(quantity) or ""
			slot.BackgroundTransparency = 0.1
		else
			hasItem = false
			shownId = nil
			thumb:ClearAllChildren()
			name.Text = ""
			qty.Text = ""
			slot.BackgroundTransparency = 0.4
		end
	end

	-- Renders a spell bind. `dimmed` marks spells of a class we're not
	-- currently playing (still bound, but not castable right now).
	local function setSpell(def, dimmed)
		local bindId = "spell:" .. def.id
		if shownId ~= bindId then
			shownId = bindId
			thumb:ClearAllChildren()
		end
		hasItem = false
		isSpell = true
		spellDimmed = dimmed == true
		name.Text = ""
		qty.Text = ""
		spellIcon.Visible = true
		spellIcon.Text = def.icon or "✦"
		spellIcon.TextTransparency = spellDimmed and 0.6 or 0
		slot.BackgroundTransparency = 0.1
		-- Unknown spells (bound while playing another class) read as gray.
		local school = Spells.getSchool(def.school)
		local schoolColor = school and school.color or Color3.fromRGB(150, 90, 255)
		stroke.Color = spellDimmed and Color3.fromRGB(105, 105, 115) or schoolColor
		stroke.Thickness = 1.5
	end

	-- fraction = remaining/cooldown (nil/0 hides the veil); manaOk dims the
	-- icon when the next cast isn't affordable.
	local function setCooldown(fraction, text, manaOk)
		if not isSpell then
			return
		end
		if fraction and fraction > 0 then
			cdVeil.Visible = true
			cdVeil.Size = UDim2.new(1, 0, math.clamp(fraction, 0, 1), 0)
			cdText.Visible = true
			cdText.Text = text or ""
		else
			cdVeil.Visible = false
			cdText.Visible = false
		end
		if not spellDimmed then
			spellIcon.TextTransparency = manaOk == false and 0.5 or 0
		end
	end

	local function setEquipped(equipped)
		if isSpell then
			return -- spell slots keep their school-colored stroke
		end
		if equipped then
			stroke.Color = Color3.fromRGB(255, 220, 120)
			stroke.Thickness = 2.5
		else
			stroke.Color = hasItem and Color3.fromRGB(120, 120, 145) or baseStroke
			stroke.Thickness = 1.5
		end
	end

	return { set = set, setSpell = setSpell, setCooldown = setCooldown, setEquipped = setEquipped, button = slot }
end

-- Finds the Tool for an item in the local player's Backpack/Character.
-- Returns (tool, isEquipped) or nil if the item has no Tool (e.g. a resource).
local function findTool(itemId)
	local character = player.Character
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		for _, t in ipairs(backpack:GetChildren()) do
			if t:IsA("Tool") and t:GetAttribute("itemId") == itemId then
				return t, false
			end
		end
	end
	if character then
		for _, t in ipairs(character:GetChildren()) do
			if t:IsA("Tool") and t:GetAttribute("itemId") == itemId then
				return t, true
			end
		end
	end
	return nil
end

-- A thin XP progress bar (no text) — the caller positions/sizes it. Reads
-- the Xp/XpToNext player attributes set by PlayerService (mirrors how the
-- mana orb reads Mana/MaxMana). The level itself is shown elsewhere now
-- (the inventory panel, next to the character), not in the HUD.
local function makeXpBar(parent, width, position, anchorPoint)
	local barBg = Instance.new("Frame")
	barBg.Size = UDim2.new(0, width, 0, 8)
	barBg.Position = position
	barBg.AnchorPoint = anchorPoint
	barBg.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
	barBg.BorderSizePixel = 0
	barBg.Parent = parent

	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(0.5, 0)
	barCorner.Parent = barBg

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1
	stroke.Color = Color3.fromRGB(70, 70, 85)
	stroke.Transparency = 0.3
	stroke.Parent = barBg

	local barFill = Instance.new("Frame")
	barFill.Size = UDim2.new(0, 0, 1, 0)
	barFill.BackgroundColor3 = Color3.fromRGB(255, 221, 51)
	barFill.BorderSizePixel = 0
	barFill.Parent = barBg

	local barFillCorner = Instance.new("UICorner")
	barFillCorner.CornerRadius = UDim.new(0.5, 0)
	barFillCorner.Parent = barFill

	local function refresh()
		local xp = player:GetAttribute("Xp") or 0
		local xpToNext = player:GetAttribute("XpToNext") or 1
		local frac = math.clamp(xp / math.max(xpToNext, 1), 0, 1)
		TweenService:Create(barFill, TweenInfo.new(0.25), { Size = UDim2.new(frac, 0, 1, 0) }):Play()
	end

	player:GetAttributeChangedSignal("Xp"):Connect(refresh)
	player:GetAttributeChangedSignal("XpToNext"):Connect(refresh)
	refresh()
end

function HudUI.start()
	-- Hide Roblox's default backpack toolbar; our hotbar replaces it.
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	end)

	local gui = Instance.new("ScreenGui")
	gui.Name = "HudUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = player:WaitForChild("PlayerGui")

	-- ---- orbs ----
	local setHealth = makeOrb(gui, "left", Color3.fromRGB(190, 45, 45), Color3.fromRGB(120, 20, 20))
	local setMana = makeOrb(gui, "right", Color3.fromRGB(50, 110, 220), Color3.fromRGB(25, 55, 130))

	-- ---- active effects (buffs/debuffs) ----
	makeEffectsPanel(gui)

	-- ---- hotbar ----
	local hotbarSize = HOTBAR_SIZE
	local PAGE_BTN_W = 26 -- page switcher at the right end of the bar
	local barWidth = hotbarSize * SLOT + (hotbarSize - 1) * SLOT_PAD + SLOT_PAD + PAGE_BTN_W
	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(0, barWidth, 0, SLOT)
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, -16)
	bar.BackgroundTransparency = 1
	bar.Parent = gui

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, SLOT_PAD)
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Parent = bar

	-- XP bar: centered, same width as the hotbar, sitting just above it.
	makeXpBar(gui, barWidth, UDim2.new(0.5, 0, 1, -(16 + SLOT + 8)), Vector2.new(0.5, 1))

	local slotItem = {} -- [i] = itemId or "spell:<id>" currently shown in slot i (or nil)

	local castSpellRemote -- resolved async in the remotes block below
	local closePicker, togglePicker -- forward-declared: built after the slots exist

	-- Activate hotbar slot i: empty bind slots open the spell picker, spell
	-- binds cast, item binds equip/unequip their Tool (no-op otherwise).
	local function activateSlot(i)
		local value = slotItem[i]
		if not value then
			if i >= WEAPON_SLOTS then
				togglePicker(i)
			end
			return
		end
		closePicker()
		local spellId = Spells.fromBind(value)
		if spellId then
			if castSpellRemote then
				castSpellRemote:FireServer(spellId)
			end
			return
		end
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			return
		end
		local tool, equipped = findTool(value)
		if not tool then
			return -- resource / not equippable
		end
		if equipped then
			humanoid:UnequipTools()
		else
			humanoid:EquipTool(tool)
		end
	end

	local slots = {}
	for i = 0, hotbarSize - 1 do
		slots[i] = makeSlot(bar, i, i < WEAPON_SLOTS, function()
			activateSlot(i)
		end)
	end

	-- ---- page switcher (three saved hotbar pages, cycled by clicking) ----
	local pageBtn = Instance.new("TextButton")
	pageBtn.Size = UDim2.new(0, PAGE_BTN_W, 0, SLOT)
	pageBtn.LayoutOrder = hotbarSize
	pageBtn.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
	pageBtn.BackgroundTransparency = 0.25
	pageBtn.BorderSizePixel = 0
	pageBtn.Font = Enum.Font.GothamBold
	pageBtn.TextSize = 18
	pageBtn.TextColor3 = Color3.fromRGB(255, 220, 120)
	pageBtn.Text = "1"
	pageBtn.Parent = bar

	local pageBtnCorner = Instance.new("UICorner")
	pageBtnCorner.CornerRadius = UDim.new(0, 6)
	pageBtnCorner.Parent = pageBtn

	local pageBtnStroke = Instance.new("UIStroke")
	pageBtnStroke.Thickness = 1.5
	pageBtnStroke.Color = Color3.fromRGB(70, 70, 85)
	pageBtnStroke.Transparency = 0.2
	pageBtnStroke.Parent = pageBtn

	local pageDots = {}
	for p = 1, HotbarBinds.pageCount do
		local dot = Instance.new("Frame")
		dot.Size = UDim2.new(0, 5, 0, 5)
		dot.AnchorPoint = Vector2.new(0.5, 1)
		dot.Position = UDim2.new(0.5, (p - 2) * 8, 1, -5)
		dot.BorderSizePixel = 0
		dot.Parent = pageBtn
		local dotCorner = Instance.new("UICorner")
		dotCorner.CornerRadius = UDim.new(1, 0)
		dotCorner.Parent = dot
		pageDots[p] = dot
	end

	local function refreshPageBtn()
		local page = HotbarBinds.activePage()
		pageBtn.Text = tostring(page)
		for p, dot in ipairs(pageDots) do
			dot.BackgroundColor3 = p == page and Color3.fromRGB(255, 220, 120) or Color3.fromRGB(90, 90, 105)
		end
	end

	pageBtn.Activated:Connect(function()
		HotbarBinds.cyclePage() -- fires changed → renderHotbar refreshes everything
	end)

	-- ---- empty-slot spell picker ----
	-- Clicking an empty bind slot lists the known spells in a panel growing
	-- upward from that slot; clicking a row binds it there.
	local pickerFrame, pickerSlot
	local PICKER_ROW = 30
	local PICKER_W = 190

	closePicker = function()
		if pickerFrame then
			pickerFrame:Destroy()
			pickerFrame, pickerSlot = nil, nil
		end
	end

	togglePicker = function(i)
		if pickerSlot == i then
			closePicker()
			return
		end
		closePicker()
		local ids = SpellsClient.list()
		if #ids == 0 then
			return
		end
		local anchor = slots[i].button

		local frame = Instance.new("Frame")
		frame.AnchorPoint = Vector2.new(0, 1)
		frame.Position = UDim2.new(0, anchor.AbsolutePosition.X, 0, anchor.AbsolutePosition.Y - 8)
		frame.Size = UDim2.new(0, PICKER_W, 0, #ids * PICKER_ROW + 26)
		frame.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
		frame.BackgroundTransparency = 0.06
		frame.BorderSizePixel = 0
		frame.Parent = gui

		local frameCorner = Instance.new("UICorner")
		frameCorner.CornerRadius = UDim.new(0, 6)
		frameCorner.Parent = frame

		local frameStroke = Instance.new("UIStroke")
		frameStroke.Thickness = 1.5
		frameStroke.Color = Color3.fromRGB(90, 90, 105)
		frameStroke.Parent = frame

		local header = Instance.new("TextLabel")
		header.Size = UDim2.new(1, -12, 0, 22)
		header.Position = UDim2.new(0, 8, 0, 2)
		header.BackgroundTransparency = 1
		header.Font = Enum.Font.GothamBold
		header.TextSize = 11
		header.TextColor3 = Color3.fromRGB(150, 150, 160)
		header.TextXAlignment = Enum.TextXAlignment.Left
		header.Text = "BIND TO KEY " .. keyLabelFor(i)
		header.Parent = frame

		for index, spellId in ipairs(ids) do
			local def = Spells.get(spellId)
			local school = def and Spells.getSchool(def.school)

			local row = Instance.new("TextButton")
			row.Size = UDim2.new(1, -8, 0, PICKER_ROW - 4)
			row.Position = UDim2.new(0, 4, 0, 24 + (index - 1) * PICKER_ROW)
			row.BackgroundColor3 = Color3.fromRGB(35, 35, 44)
			row.AutoButtonColor = true
			row.BorderSizePixel = 0
			row.Font = Enum.Font.GothamMedium
			row.TextSize = 13
			row.TextColor3 = Color3.new(1, 1, 1)
			row.TextXAlignment = Enum.TextXAlignment.Left
			row.Text = ("    %s  %s"):format(def.icon or "✦", def.name)
			row.Parent = frame

			local rowCorner = Instance.new("UICorner")
			rowCorner.CornerRadius = UDim.new(0, 4)
			rowCorner.Parent = row

			local accent = Instance.new("Frame")
			accent.Size = UDim2.new(0, 3, 1, -8)
			accent.Position = UDim2.new(0, 3, 0, 4)
			accent.BackgroundColor3 = school and school.color or Color3.fromRGB(150, 90, 255)
			accent.BorderSizePixel = 0
			accent.Parent = row

			row.Activated:Connect(function()
				HotbarBinds.set(i, Spells.toBind(spellId))
				closePicker()
			end)
		end

		pickerFrame, pickerSlot = frame, i
	end

	-- Highlight the slot whose item is currently equipped.
	local function refreshEquipped()
		local equippedId
		local character = player.Character
		local tool = character and character:FindFirstChildOfClass("Tool")
		if tool then
			equippedId = tool:GetAttribute("itemId")
		end
		for i = 0, hotbarSize - 1 do
			slots[i].setEquipped(slotItem[i] ~= nil and slotItem[i] == equippedId)
		end
	end

	local lastInventory = nil

	local function renderHotbar(inventory)
		if typeof(inventory) == "table" then
			lastInventory = inventory
		end
		-- Until the first real inventory arrives, never judge binds against
		-- it — clearing here would wipe freshly-seeded persisted binds.
		local hasInventory = lastInventory ~= nil
		inventory = lastInventory or {}

		-- Slots 1/2 mirror the paper doll's weapon/offhand; the rest are binds.
		local weaponEntries = {}
		local mainByItem = {} -- [itemId] = first main-grid entry (for binds)
		for _, entry in ipairs(inventory) do
			if entry.containerId == "equipment" then
				weaponEntries[entry.x] = entry
			elseif entry.containerId == "main" and not mainByItem[entry.itemId] then
				mainByItem[entry.itemId] = entry
			end
		end

		for i = 0, WEAPON_SLOTS - 1 do
			local entry = weaponEntries[i]
			slotItem[i] = entry and entry.itemId or nil
			slots[i].set(slotItem[i], entry and entry.quantity or nil)
		end

		for i = WEAPON_SLOTS, hotbarSize - 1 do
			local bindValue = HotbarBinds.get(i)
			local spellId = bindValue and Spells.fromBind(bindValue)
			if spellId then
				-- Spell binds don't live in the inventory; render from the
				-- shared defs, dimmed when the active class doesn't know it.
				local spellDef = Spells.get(spellId)
				if spellDef then
					slotItem[i] = bindValue
					slots[i].setSpell(spellDef, not SpellsClient.isKnown(spellId))
				else
					HotbarBinds.clear(i) -- bind to a spell that no longer exists
					slotItem[i] = nil
					slots[i].set(nil)
				end
			else
				local itemId = bindValue
				local entry = itemId and mainByItem[itemId]
				if itemId and not entry and hasInventory then
					-- The bound item left the grid; drop the bind (fires changed,
					-- which re-renders — by then the bind is gone, so it settles).
					HotbarBinds.clear(i)
				end
				slotItem[i] = entry and entry.itemId or nil
				slots[i].set(slotItem[i], entry and entry.quantity or nil)
			end
		end
		refreshEquipped()
		refreshPageBtn()
		closePicker() -- the world changed under the picker; drop it
	end

	renderHotbar(nil) -- start as empty sockets
	HotbarBinds.changed:Connect(function()
		renderHotbar(nil) -- re-render with the last known inventory
	end)
	SpellsClient.changed:Connect(function()
		renderHotbar(nil) -- known-spells set changed: (un)dim spell slots
	end)

	-- Cooldown sweep for spell slots: drains the veil from the SpellCd_<id>
	-- attributes (server-clock expiries) and dims icons we can't afford.
	task.spawn(function()
		while true do
			task.wait(0.1)
			local now = Workspace:GetServerTimeNow()
			local mana = player:GetAttribute("Mana") or 0
			for i = WEAPON_SLOTS, hotbarSize - 1 do
				local spellId = slotItem[i] and Spells.fromBind(slotItem[i])
				local def = spellId and Spells.get(spellId)
				if def then
					local manaOk = mana >= (def.manaCost or 0)
					local expiry = player:GetAttribute(Spells.cdAttributeFor(spellId))
					local remaining = typeof(expiry) == "number" and (expiry - now) or 0
					if remaining > 0 and (def.cooldown or 0) > 0 then
						local text = remaining >= 10 and string.format("%d", remaining)
							or string.format("%.1f", remaining)
						slots[i].setCooldown(remaining / def.cooldown, text, manaOk)
					else
						slots[i].setCooldown(nil, nil, manaOk)
					end
				end
			end
		end
	end)

	-- Number keys 1..9,0 equip/unequip the matching slot. While the inventory
	-- panel is open the keys belong to it (3–0 assign quick binds there), and
	-- while hovering a tracker spell row they bind instead (SpellTrackerUI).
	for i = 0, hotbarSize - 1 do
		local keyCode = NUMBER_KEYS[i + 1]
		if keyCode then
			ContextActionService:BindAction("Hotbar" .. i, function(_, inputState)
				if inputState == Enum.UserInputState.Begin
					and not ClientState.inventoryOpen
					and not ClientState.spellHover then
					activateSlot(i)
				end
				return Enum.ContextActionResult.Pass
			end, false, keyCode)
		end
	end

	-- X is the fast page swap (same as clicking the switcher button).
	ContextActionService:BindAction("HotbarPage", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			HotbarBinds.cyclePage()
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.X)

	-- ---- health binding ----
	local function bindCharacter(character)
		local humanoid = character:WaitForChild("Humanoid")
		local function update()
			setHealth(humanoid.Health, humanoid.MaxHealth)
		end
		humanoid.HealthChanged:Connect(update)
		humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(update)
		update()

		-- Keep the equipped-slot highlight in sync as tools are (un)equipped.
		character.ChildAdded:Connect(function(child)
			if child:IsA("Tool") then
				refreshEquipped()
			end
		end)
		character.ChildRemoved:Connect(function(child)
			if child:IsA("Tool") then
				refreshEquipped()
			end
		end)
		refreshEquipped()
	end
	if player.Character then
		bindCharacter(player.Character)
	end
	player.CharacterAdded:Connect(bindCharacter)

	-- ---- mana binding (Player attributes) ----
	local function updateMana()
		setMana(player:GetAttribute("Mana") or 0, player:GetAttribute("MaxMana") or Config.Mana.max)
	end
	player:GetAttributeChangedSignal("Mana"):Connect(updateMana)
	player:GetAttributeChangedSignal("MaxMana"):Connect(updateMana)
	updateMana()

	-- ---- inventory → hotbar ----
	task.spawn(function()
		castSpellRemote = Remotes.get("CastSpell")

		local inventoryUpdated = Remotes.get("InventoryUpdated")
		inventoryUpdated.OnClientEvent:Connect(renderHotbar)

		local requestInventory = Remotes.getFunction("RequestInventory")
		local ok, inventory = pcall(function()
			return requestInventory:InvokeServer()
		end)
		if ok then
			renderHotbar(inventory)
		end
	end)
end

return HudUI
