-- Diablo-style HUD: a health orb (bottom-left), a mana orb (bottom-right), and
-- a functional hotbar of item sockets between them.
--   * Health reads the local Humanoid directly (HP replicates automatically).
--   * Mana reads the "Mana"/"MaxMana" Player attributes set by the server's
--     ManaService (attributes replicate to the owner, so no remote is needed).
--   * The hotbar: slots 1/2 are reserved for the equipped
--     main weapons (the paper doll's weapon/offhand slots) and slots 3–0 are
--     player-assigned quick binds (hover an item in the inventory grid and
--     press the key — see HotbarBinds). Clicking a slot (or pressing its
--     number key) equips/unequips that item's Tool. We hide Roblox's default
--     backpack bar so this is the only hotbar on screen.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")
local StarterGui = game:GetService("StarterGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Items = require(Shared:WaitForChild("Items"))
local ItemModels = require(Shared:WaitForChild("ItemModels"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Config = require(Shared:WaitForChild("Config"))
local HotbarBinds = require(script.Parent.HotbarBinds)
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

	slot.Activated:Connect(onActivated)

	local hasItem = false
	local shownId = nil -- itemId whose thumbnail is currently rendered
	local function set(itemId, quantity)
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

	local function setEquipped(equipped)
		if equipped then
			stroke.Color = Color3.fromRGB(255, 220, 120)
			stroke.Thickness = 2.5
		else
			stroke.Color = hasItem and Color3.fromRGB(120, 120, 145) or baseStroke
			stroke.Thickness = 1.5
		end
	end

	return { set = set, setEquipped = setEquipped }
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

	-- ---- hotbar ----
	local hotbarSize = HOTBAR_SIZE
	local barWidth = hotbarSize * SLOT + (hotbarSize - 1) * SLOT_PAD
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

	local slotItem = {} -- [i] = itemId currently shown in slot i (or nil)

	-- Equip/unequip the item in hotbar slot i (no-op for non-equippables).
	local function activateSlot(i)
		local itemId = slotItem[i]
		if not itemId then
			return
		end
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			return
		end
		local tool, equipped = findTool(itemId)
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
			local itemId = HotbarBinds.get(i)
			local entry = itemId and mainByItem[itemId]
			if itemId and not entry and hasInventory then
				-- The bound item left the grid; drop the bind (fires changed,
				-- which re-renders — by then the bind is gone, so it settles).
				HotbarBinds.clear(i)
			end
			slotItem[i] = entry and entry.itemId or nil
			slots[i].set(slotItem[i], entry and entry.quantity or nil)
		end
		refreshEquipped()
	end

	renderHotbar(nil) -- start as empty sockets
	HotbarBinds.changed:Connect(function()
		renderHotbar(nil) -- re-render with the last known inventory
	end)

	-- Number keys 1..9,0 equip/unequip the matching slot. While the inventory
	-- panel is open the keys belong to it (3–0 assign quick binds there).
	for i = 0, hotbarSize - 1 do
		local keyCode = NUMBER_KEYS[i + 1]
		if keyCode then
			ContextActionService:BindAction("Hotbar" .. i, function(_, inputState)
				if inputState == Enum.UserInputState.Begin and not ClientState.inventoryOpen then
					activateSlot(i)
				end
				return Enum.ContextActionResult.Pass
			end, false, keyCode)
		end
	end

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
